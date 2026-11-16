-- Boom skillchain coordinator: pure planner.
--
-- No Windower calls. Given every member's offer, the target's current chain
-- state and the options, it returns one plan. Keep it this way so it can be
-- unit-tested offline and moved into Trust unchanged.
--
-- Input
--   members = { { name=, tp=, abilities = { { kind='ws'|'bp', id=, name=, ready=bool }, ... } }, ... }
--   current = nil, or { step=n, chain='Fusion' or nil, props={...} } for an open window
--   options = see planner.default_options
--   data    = adapter from sc/trust_data.lua
--
-- Output
--   { action='execute', steps={ {member=, kind=, id=, name=, makes=} }, chain=, level=, reason= }
--   { action='hold', reason=, steps=..., best=... }   -- waiting for a 3-step chain
--   { action='none', reason= }

local planner = {}

planner.default_options = {
    max_steps = 3,          -- longest chain to plan (counting from the opener)
    hold_for_three = false, -- save TP for a 3-step chain when the party could make one
    hold_max_tp = 3000,     -- stop holding once a ready weapon-skill member reaches this TP
    targets = {},           -- preferred chain properties or elements, e.g. {'Light','Fusion','Fire'}
    openers = {},           -- preferred openers: { {member=nil|'Name', ability='Savage Blade'} }
    allow_bp = true,        -- include Blood Pact: Rage
    mixed = true,           -- a member may give one weapon skill and one blood pact in a chain
}

local function lower(s) return type(s) == 'string' and s:lower() or s end

local function merged_options(options)
    local result = {}
    for k, v in pairs(planner.default_options) do result[k] = v end
    for k, v in pairs(options or {}) do result[k] = v end
    return result
end

local element_aliases = { thunder = 'lightning', darkness = 'dark' }

-- Does a finished chain match one of the requested properties or elements?
local function matches_target(chain, targets, data)
    if not chain or #targets == 0 then return false end
    local chain_l = lower(chain)
    local elements = data.elements(chain)
    for _, t in ipairs(targets) do
        local tl = lower(t)
        if tl == chain_l or (tl == 'light' and chain_l == 'light lv.4')
            or (tl == 'darkness' and chain_l == 'darkness lv.4') then
            return true
        end
        -- Names that are not properties (Fire, Ice, Thunder...) match by element.
        local el = element_aliases[tl] or tl
        if not data.is_property(t) then
            for _, e in ipairs(elements) do
                if lower(e) == el then return true end
            end
        end
    end
    return false
end

local function opener_matches(step, openers)
    for _, o in ipairs(openers) do
        local name_ok = lower(o.ability) == lower(step.name)
        local member_ok = (o.member == nil or o.member == '' or lower(o.member) == lower(step.member))
        if name_ok and member_ok then return true end
    end
    return false
end

-- Collapse abilities that behave identically for chaining (same member, kind,
-- property list). Keeps search small; a preferred opener wins the slot.
local function candidate_list(members, options, data, include_unready)
    local list = {}
    for _, m in ipairs(members) do
        local seen = {}
        for _, a in ipairs(m.abilities or {}) do
            local usable = (a.ready or include_unready) and (a.kind ~= 'bp' or options.allow_bp)
            local props = usable and data.props(a.kind, a.id) or {}
            if usable and #props > 0 then
                local sig = a.kind .. ':' .. table.concat(props, ',')
                local entry = {
                    member = m.name, kind = a.kind, id = a.id,
                    name = a.name or data.name(a.kind, a.id) or tostring(a.id),
                    props = props, delay = data.delay(a.kind, a.id), tp = m.tp or 0,
                }
                local existing = seen[sig]
                if not existing then
                    seen[sig] = entry
                    list[#list + 1] = entry
                elseif opener_matches(entry, options.openers) and not opener_matches(existing, options.openers) then
                    for i, e in ipairs(list) do
                        if e == existing then list[i] = entry end
                    end
                    seen[sig] = entry
                end
            end
        end
    end
    return list
end

-- Compare two scored plans; true when a is better than b.
local function better(a, b)
    if b == nil then return true end
    for i = 1, #a.score do
        if a.score[i] ~= b.score[i] then return a.score[i] > b.score[i] end
    end
    return a.key < b.key -- deterministic tie-break
end

local function score_plan(plan, options, data, fresh)
    local target = (#options.targets > 0 and matches_target(plan.chain, options.targets, data)) and 1 or 0
    local opener = (fresh and #options.openers > 0 and opener_matches(plan.steps[1], options.openers)) and 1 or 0
    -- Order: requested property/element, requested opener, chain level, more
    -- steps (each step is another magic burst window for Boom).
    return { target, opener, data.level(plan.chain), #plan.steps }
end

-- Depth-first search over ordered ability sequences.
local function search(candidates, current, options, data)
    local best = nil
    local fresh = current == nil
    local start_step = current and current.step or 0
    local used = {}
    local steps = {}

    local function slot(c) return options.mixed and (c.member .. ':' .. c.kind) or c.member end

    local function consider(chain)
        if not chain then return end
        local plan = { steps = {}, chain = chain }
        local keys = {}
        for i, s in ipairs(steps) do
            plan.steps[i] = s
            keys[i] = s.member .. '/' .. s.name
        end
        plan.key = table.concat(keys, '>')
        plan.score = score_plan(plan, options, data, fresh)
        if better(plan, best) then best = plan end
    end

    local function walk(prev_props, prev_chain, depth)
        if start_step + depth >= options.max_steps then return end
        if prev_chain and data.is_closed(prev_chain) then return end
        for _, c in ipairs(candidates) do
            local s = slot(c)
            if not used[s] then
                local made
                if prev_props == nil then
                    made = nil -- opener
                else
                    made = data.combine_lists(prev_chain and { prev_chain } or prev_props, c.props)
                end
                if prev_props == nil or made then
                    used[s] = true
                    steps[#steps + 1] = {
                        member = c.member, kind = c.kind, id = c.id, name = c.name,
                        delay = c.delay, makes = made, tp = c.tp,
                    }
                    if made then consider(made) end
                    walk(c.props, made, depth + 1)
                    steps[#steps] = nil
                    used[s] = nil
                end
            end
        end
    end

    if fresh then
        walk(nil, nil, 0)
    else
        local props = current.chain and { current.chain } or (current.props or {})
        walk(props, current.chain, 0)
    end
    return best
end

function planner.plan(input)
    local data = input.data
    local options = merged_options(input.options)
    local current = input.current
    if current and current.chain and data.is_closed(current.chain) then
        current = nil -- closed chain: a new one starts from an opener
    end

    local ready = candidate_list(input.members or {}, options, data, false)
    local best = search(ready, current, options, data)

    if current == nil and options.hold_for_three and options.max_steps >= 3 then
        local potential = search(candidate_list(input.members or {}, options, data, true), nil, options, data)
        local best_steps = best and #best.steps or 0
        if potential and #potential.steps >= 3 and best_steps < 3 then
            local capped = false
            for _, c in ipairs(ready) do
                if c.kind == 'ws' and (c.tp or 0) >= options.hold_max_tp then capped = true end
            end
            if not capped then
                return { action = 'hold', best = best, potential = potential,
                    reason = 'Saving TP: party can make 3 steps (' .. potential.chain .. ')' }
            end
        end
    end

    if not best then
        if current then
            return { action = 'none', reason = 'No ready ability continues ' .. tostring(current.chain or 'the opener') }
        end
        return { action = 'none', reason = 'No 2-step chain from ready abilities' }
    end
    -- Don't continue a chain that already is a requested target into one that isn't.
    if current and current.chain and #options.targets > 0 and best.score[1] == 0
        and matches_target(current.chain, options.targets, data) then
        return { action = 'none', reason = 'Keeping target ' .. current.chain .. '; no continuation stays on target' }
    end
    local target_note = ''
    if #options.targets > 0 and best.score[1] == 0 then
        target_note = ' (target not possible; fallback)'
    end
    return {
        action = 'execute', steps = best.steps, chain = best.chain,
        level = data.level(best.chain), continuing = current ~= nil,
        reason = 'Best: ' .. best.chain .. target_note,
    }
end

-- Readable one-line plan text, e.g. "Clairvaux Savage Blade > Myrr Flaming Crush = Fusion"
function planner.describe(plan)
    local parts = {}
    for _, s in ipairs(plan.steps or {}) do
        parts[#parts + 1] = s.member .. ' ' .. s.name
    end
    return table.concat(parts, ' > ') .. ' = ' .. tostring(plan.chain)
end

return planner
