-- Boom skillchain coordinator: game I/O around the pure planner.
--
-- Every client running Boom runs one coordinator. Clients talk over Windower
-- IPC (same PC only). Flow:
--   1. A client becomes ready (1000+ TP while engaged, or Blood Pact: Rage
--      ready with a pet out) and polls with its target mob.
--   2. Party members reply with offers: TP and every chain-capable ability,
--      each marked ready / not ready.
--   3. The poller plans with sc/planner.lua and sends the plan.
--   4. Each member in the plan re-checks its own ability and acknowledges.
--   5. On all acks the poller sends go. Step 1 fires; each later step fires
--      when the previous step's action packet is seen, after that ability's
--      chain delay (Trust: 3s unless skills.lua says otherwise) plus a margin.
--   Any refusal, miss, unexpected action, broken chain or timeout aborts the
--   plan everywhere; members may poll again from the current window.

local planner = require('sc/planner')
local protocol = require('sc/protocol')

local coordinator = {}
coordinator.__index = coordinator

-- Trust action_message_util.weapon_skill_message_ids (hits that apply properties).
local HIT_MESSAGES = { [2]=true, [110]=true, [185]=true, [187]=true, [317]=true, [529]=true, [802]=true }

-- Skillchain effect ids -> chain name (same ids Boom bursts on).
local CHAIN_EFFECTS = {
    [288]='Light', [289]='Darkness', [290]='Gravitation', [291]='Fragmentation', [292]='Distortion',
    [293]='Fusion', [294]='Compression', [295]='Liquefaction', [296]='Induration', [297]='Reverberation',
    [298]='Transfixion', [299]='Scission', [300]='Detonation', [301]='Impaction',
    [385]='Light', [386]='Darkness', [387]='Gravitation', [388]='Fragmentation', [389]='Distortion',
    [390]='Fusion', [391]='Compression', [392]='Liquefaction', [393]='Induration', [394]='Reverberation',
    [395]='Transfixion', [396]='Scission', [397]='Detonation', [398]='Impaction',
    [767]='Radiance', [769]='Radiance', [768]='Umbra', [770]='Umbra',
}
coordinator.CHAIN_EFFECTS = CHAIN_EFFECTS

-- Status buffs that block the action (Trust weapon_skill.lua / blood_pact_rage.lua).
-- sleep 2/19, petrification 7, charm 14/17, terror 28, amnesia 16, stun 10, invisible 69.
local WS_BLOCK = { [2]=true, [19]=true, [7]=true, [14]=true, [17]=true, [28]=true, [16]=true, [10]=true }
local BP_BLOCK = { [2]=true, [19]=true, [7]=true, [14]=true, [17]=true, [28]=true, [16]=true, [69]=true }

-- Trust battle_util range multipliers for weapon skill reach.
local RANGE_MULT = { [2]=1.55, [3]=1.490909, [4]=1.44, [5]=1.377778, [6]=1.30, [7]=1.15,
    [8]=1.25, [9]=1.377778, [10]=1.45, [11]=1.454545454545455, [12]=1.666666666666667 }

local BP_RANGE = 21 -- Inferred: summoner-to-mob limit for Blood Pact: Rage; confirm live.

coordinator.default_settings = {
    enabled = true,
    max_steps = 3,
    hold_for_three = false,
    hold_max_tp = 3000,
    min_tp = 1000,
    allow_bp = true,
    mixed = true,
    targets = '',        -- comma list: Light,Fusion,Fire
    openers = '',        -- comma list: Savage Blade,Cioara:Flaming Crush
    announce = 'local',  -- local | party | off
    poll_window = 0.5,
    ack_window = 0.7,
    step_margin = 0.4,
    step_timeout = 6,
    retry_delay = 1.5,
    trust_path = '',
}

-- env: windower, res, data (trust_data adapter), settings, save(), now(), schedule(fn, delay),
--      chat = { message(text), notice(heading, text), debug(text), colored(v, c) }
function coordinator.new(env)
    local self = setmetatable({
        env = env,
        w = env.windower,
        res = env.res,
        data = env.data,
        settings = env.settings,
        chains = {},
        poll = nil,
        plan = nil,
        retry_at = 0,
        counter = 0,
        last_tick = -1,
        last_plan = 'None',
        last_result = 'None',
    }, coordinator)
    return self
end

----------------------------------------------------------------------------
-- small helpers

function coordinator:now() return self.env.now() end
function coordinator:say(text) self.env.chat.message(text) end
function coordinator:note(h, t) self.env.chat.notice(h, t) end
function coordinator:dbg(text) self.env.chat.debug('SC: ' .. text) end

function coordinator:send(kind, ...)
    self.w.send_ipc_message(protocol.encode(kind, ...))
end

function coordinator:player() return self.w.ffxi.get_player() end

function coordinator:my_name()
    local p = self:player()
    return p and p.name or nil
end

local function split_list(text)
    local list = {}
    for item in tostring(text or ''):gmatch('[^,]+') do
        item = item:gsub('^%s+', ''):gsub('%s+$', '')
        if item ~= '' then list[#list + 1] = item end
    end
    return list
end
coordinator.split_list = split_list

function coordinator:options()
    local s = self.settings
    local openers = {}
    for _, item in ipairs(split_list(s.openers)) do
        local member, ability = item:match('^([^:]+):(.+)$')
        openers[#openers + 1] = { member = member, ability = ability or item }
    end
    return {
        max_steps = tonumber(s.max_steps) or 3,
        hold_for_three = s.hold_for_three == true,
        hold_max_tp = tonumber(s.hold_max_tp) or 3000,
        targets = split_list(s.targets),
        openers = openers,
        allow_bp = s.allow_bp ~= false,
        mixed = s.mixed ~= false,
    }
end

-- name -> { id=, pet_id= } for party and alliance members in range of data
function coordinator:party_map()
    local map, by_id = {}, {}
    local party = self.w.ffxi.get_party() or {}
    for key, member in pairs(party) do
        if type(member) == 'table' and member.name and type(key) == 'string'
            and (key:match('^p%d$') or key:match('^a%d%d$')) then
            local mob = member.mob
            local entry = { name = member.name, id = mob and mob.id or nil }
            if mob and mob.pet_index then
                local pet = self.w.ffxi.get_mob_by_index(mob.pet_index)
                entry.pet_id = pet and pet.id or nil
            end
            map[member.name] = entry
            if entry.id then by_id[entry.id] = member.name end
            if entry.pet_id then by_id[entry.pet_id] = member.name end
        end
    end
    return map, by_id
end

function coordinator:in_party(name)
    local map = self:party_map()
    return map[name] ~= nil
end

local function has_block(player, blocked)
    for _, buff in ipairs(player.buffs or {}) do
        if blocked[buff] then return true end
    end
    return false
end

local function distance(mob)
    return mob and mob.distance and math.sqrt(mob.distance) or 999
end

function coordinator:valid_mob(mob_id)
    local mob = mob_id and self.w.ffxi.get_mob_by_id(mob_id)
    if not mob or not mob.is_npc or not mob.valid_target or (mob.hpp or 0) <= 0 then return nil end
    return mob
end

-- Mob this client would fight: <t> while engaged, else <bt>.
function coordinator:fight_target()
    local player = self:player()
    if not player then return nil end
    if player.status == 1 then
        local t = self.w.ffxi.get_mob_by_target('t')
        if t and self:valid_mob(t.id) then return t.id end
    end
    local bt = self.w.ffxi.get_mob_by_target('bt')
    if bt and self:valid_mob(bt.id) then return bt.id end
    return nil
end

function coordinator:engaged_on(mob_id)
    local player = self:player()
    if not player or player.status ~= 1 then return false end
    local t = self.w.ffxi.get_mob_by_target('t')
    local bt = self.w.ffxi.get_mob_by_target('bt')
    return (t and t.id == mob_id) or (bt and bt.id == mob_id) or false
end

function coordinator:ws_reach(ws_id, mob)
    local ws = self.res.weapon_skills[ws_id]
    if not ws or not ws.range then return 999 end
    local me = self.w.ffxi.get_mob_by_id(self:player().id) or {}
    return (mob.model_size or 0) + ws.range * (RANGE_MULT[ws.range] or 1) + (me.model_size or 0)
end

-- nil when usable now, else a short reason.
function coordinator:ws_blocker(ws_id, mob_id)
    local player = self:player()
    if not player then return 'no player' end
    local tp = player.vitals and player.vitals.tp or 0
    if tp < (tonumber(self.settings.min_tp) or 1000) then return 'TP ' .. tp end
    if has_block(player, WS_BLOCK) then return 'status prevents weapon skills' end
    if not self:engaged_on(mob_id) then return 'not engaged on target' end
    local mob = self:valid_mob(mob_id)
    if not mob then return 'target gone' end
    if distance(mob) > self:ws_reach(ws_id, mob) then return 'out of weapon skill range' end
    return nil
end

function coordinator:bp_recast_ready()
    local ja = self.res.job_abilities:with('en', 'Blood Pact: Rage')
    if not ja then return false end
    local recasts = self.w.ffxi.get_ability_recasts() or {}
    return (recasts[ja.recast_id] or 0) == 0
end

function coordinator:bp_blocker(mob_id)
    local player = self:player()
    if not player then return 'no player' end
    if self.settings.allow_bp == false then return 'blood pacts off' end
    if not self.w.ffxi.get_mob_by_target('pet') then return 'no pet' end
    local info = self.w.ffxi.get_info() or {}
    if info.mog_house then return 'in Mog House' end
    if has_block(player, BP_BLOCK) then return 'status prevents blood pacts' end
    if not self:bp_recast_ready() then return 'Blood Pact: Rage recast' end
    local mob = self:valid_mob(mob_id)
    if not mob then return 'target gone' end
    if distance(mob) > BP_RANGE then return 'out of blood pact range' end
    return nil
end

function coordinator:known_abilities()
    local abilities = self.w.ffxi.get_abilities() or {}
    local ws, bp = {}, {}
    for _, id in ipairs(abilities.weapon_skills or {}) do
        if #self.data.props('ws', id) > 0 then ws[#ws + 1] = id end
    end
    if self.w.ffxi.get_mob_by_target('pet') then
        for _, id in ipairs(abilities.job_abilities or {}) do
            if #self.data.props('bp', id) > 0 then bp[#bp + 1] = id end
        end
    end
    return ws, bp
end

-- This client's offer for a mob: every chain-capable ability, marked ready or not.
-- Not-ready abilities are included only when they could become ready in this
-- fight (engaged on the mob / pet out); the planner uses them only for holds.
function coordinator:build_offer(mob_id)
    local player = self:player()
    if not player then return nil end
    local ws, bp = self:known_abilities()
    local list = {}
    local engaged = self:engaged_on(mob_id)
    for _, id in ipairs(ws) do
        local blocker = self:ws_blocker(id, mob_id)
        if engaged or not blocker then
            list[#list + 1] = { kind = 'ws', id = id, ready = blocker == nil }
        end
    end
    if self.settings.allow_bp ~= false then
        local blocker = self:bp_blocker(mob_id)
        for _, id in ipairs(bp) do
            list[#list + 1] = { kind = 'bp', id = id, ready = blocker == nil }
        end
    end
    return { name = player.name, tp = player.vitals and player.vitals.tp or 0, abilities = list }
end

function coordinator:offer_has_ready(offer)
    for _, a in ipairs(offer and offer.abilities or {}) do
        if a.ready then return true end
    end
    return false
end

function coordinator:ability_name(kind, id)
    local r = (kind == 'bp') and self.res.job_abilities[id] or self.res.weapon_skills[id]
    return (r and r.en) or self.data.name(kind, id) or tostring(id)
end

----------------------------------------------------------------------------
-- skillchain tracker (mirrors Trust SkillchainTracker on plain tables)

-- Current open chain on a mob, as planner input, or nil.
function coordinator:current_chain(mob_id)
    local c = self.chains[mob_id]
    if not c then return nil end
    local now = self:now()
    if now >= c.expires - 1.0 then return nil end -- too little window left to use
    if c.chain and self.data.is_closed(c.chain) then return nil end
    return { step = c.step, chain = c.chain, props = c.props, opens = c.start + c.delay }
end

function coordinator:record_step(mob_id, kind, id, effect_id)
    local now = self:now()
    local props = self.data.props(kind, id)
    local current = self.chains[mob_id]
    if current and now >= current.expires then current = nil end
    local step, chain
    local made = effect_id and CHAIN_EFFECTS[effect_id]
    if made then
        chain = made
        if current and current.chain then
            chain = self.data.combine(current.chain, made) or made
        end
        step = current and (current.step + 1) or 2
    else
        step = 1
    end
    local delay = self.data.delay(kind, id)
    self.chains[mob_id] = {
        step = step, chain = chain, props = props, delay = delay,
        start = now, expires = now + delay + 8 - step,
    }
    return self.chains[mob_id]
end

----------------------------------------------------------------------------
-- polling (leader side)

function coordinator:can_poll()
    if not self.settings.enabled or not self.data then return false end
    if self.poll or self.plan then return false end
    if self:now() < self.retry_at then return false end
    return true
end

function coordinator:start_poll(mob_id)
    local name = self:my_name()
    self.counter = self.counter + 1
    local pid = protocol.make_poll_id(os.time(), name, self.counter)
    local own = self:build_offer(mob_id)
    self.poll = {
        pid = pid, mob = mob_id, phase = 'offers',
        offers = { [name] = own }, order = { name },
        deadline = self:now() + (tonumber(self.settings.poll_window) or 0.5),
    }
    self:dbg('Poll ' .. pid .. ' on mob ' .. tostring(mob_id))
    self:send('poll', pid, name, mob_id)
end

function coordinator:finish_offers()
    local poll = self.poll
    local members = {}
    table.sort(poll.order)
    for _, name in ipairs(poll.order) do
        local offer = poll.offers[name]
        if offer then
            for _, a in ipairs(offer.abilities) do a.name = self:ability_name(a.kind, a.id) end
            members[#members + 1] = offer
        end
    end
    local current = self:current_chain(poll.mob)
    local result = planner.plan({ members = members, current = current,
        options = self:options(), data = self.data })
    self.last_result = result.action .. ': ' .. tostring(result.reason)
    if result.action ~= 'execute' then
        self:dbg(result.reason)
        self:send('result', poll.pid, result.action, result.reason)
        self:end_poll(result.action == 'hold' and 'hold' or 'none')
        return
    end
    poll.plan = result
    poll.phase = 'acks'
    poll.acks = {}
    poll.deadline = self:now() + (tonumber(self.settings.ack_window) or 0.7)
    self:send('plan', poll.pid, poll.mob, result.chain, protocol.encode_steps(result.steps))
    self:dbg('Plan ' .. planner.describe(result))
    -- the leader acknowledges its own steps directly
    local me = self:my_name()
    for i, s in ipairs(result.steps) do
        if s.member == me then
            local ok, why = self:validate_step(poll.mob, s, i, current ~= nil)
            poll.acks[me] = ok and 'ok' or why
        end
    end
    self:check_acks()
end

function coordinator:check_acks()
    local poll = self.poll
    if not poll or poll.phase ~= 'acks' then return end
    local pending = false
    for _, s in ipairs(poll.plan.steps) do
        local ack = poll.acks[s.member]
        if ack == nil then
            pending = true
        elseif ack ~= 'ok' then
            self:dbg(s.member .. ' refused: ' .. ack)
            self:send('result', poll.pid, 'refused', s.member .. ': ' .. ack)
            self.last_result = 'refused: ' .. s.member .. ': ' .. ack
            self:end_poll('none')
            return
        end
    end
    if pending then return end
    local plan_steps = protocol.encode_steps(poll.plan.steps)
    self:send('go', poll.pid, poll.mob, poll.plan.chain, plan_steps)
    local plan = poll.plan
    local mob = poll.mob
    local pid = poll.pid
    self.poll = nil
    self:begin_plan(pid, mob, plan.chain, plan.steps, self:my_name())
end

function coordinator:end_poll(outcome)
    self.poll = nil
    self.retry_at = self:now() + (tonumber(self.settings.retry_delay) or 1.5)
end

----------------------------------------------------------------------------
-- member side

-- Can this client do its plan step? Step 1 must be usable now; later steps
-- must be usable now too (the planner only uses ready abilities).
function coordinator:validate_step(mob_id, step)
    if step.member ~= self:my_name() then return true end
    local ws, bp = self:known_abilities()
    local list = step.kind == 'bp' and bp or ws
    local known = false
    for _, id in ipairs(list) do if id == step.id then known = true end end
    if not known then return false, 'does not have ' .. self:ability_name(step.kind, step.id) end
    -- (not "a and b or c": a nil blocker from bp_blocker means usable)
    local blocker
    if step.kind == 'bp' then
        blocker = self:bp_blocker(mob_id)
    else
        blocker = self:ws_blocker(step.id, mob_id)
    end
    if blocker then return false, blocker end
    return true
end

function coordinator:on_ipc(message)
    local kind, f = protocol.decode(message)
    if not kind then return end
    if kind == 'set' then
        self:apply_setting(f[1], f[2], true)
        return
    end
    if not self.data then return end
    local me = self:my_name()
    if not me then return end

    if kind == 'poll' then
        local pid, leader, mob = f[1], f[2], tonumber(f[3])
        if leader == me or not self:in_party(leader) or not self.settings.enabled then return end
        if self.plan then
            self:send('busy', pid, me, self.plan.pid)
            return
        end
        if self.poll then
            if protocol.poll_before(self.poll.pid, pid) then return end -- mine wins
            self:dbg('Yielding poll ' .. self.poll.pid .. ' to ' .. pid)
            self.poll = nil
        end
        local offer = self:build_offer(mob)
        if offer then
            self:send('offer', pid, me, offer.tp, protocol.encode_abilities(offer.abilities))
        end
    elseif kind == 'offer' then
        local poll = self.poll
        local pid, name = f[1], f[2]
        if not poll or poll.pid ~= pid or poll.phase ~= 'offers' or not self:in_party(name) then return end
        if not poll.offers[name] then poll.order[#poll.order + 1] = name end
        poll.offers[name] = { name = name, tp = tonumber(f[3]) or 0, abilities = protocol.decode_abilities(f[4]) }
    elseif kind == 'busy' then
        if self.poll and self.poll.pid == f[1] then
            self:dbg(f[2] .. ' is busy with ' .. tostring(f[3]))
            self:end_poll('none')
        end
    elseif kind == 'plan' then
        local pid, mob = f[1], tonumber(f[2])
        local steps = protocol.decode_steps(f[4])
        for i, s in ipairs(steps) do
            if s.member == me then
                local ok, why = self:validate_step(mob, s, i)
                self:send('ack', pid, me, ok and 'ok' or why)
                break
            end
        end
    elseif kind == 'ack' then
        local poll = self.poll
        if poll and poll.pid == f[1] and poll.phase == 'acks' then
            poll.acks[f[2]] = f[3]
            self:check_acks()
        end
    elseif kind == 'go' then
        local pid, mob, chain = f[1], tonumber(f[2]), f[3]
        local steps = protocol.decode_steps(f[4])
        if self.poll and self.poll.pid ~= pid then self.poll = nil end
        local leader = pid:match('^%d+%.(.+)%.%d+$')
        self:begin_plan(pid, mob, chain, steps, leader)
    elseif kind == 'result' then
        -- someone's poll ended without a plan; avoid immediately re-polling the same state
        if not self.poll then
            self.retry_at = math.max(self.retry_at, self:now() + (tonumber(self.settings.retry_delay) or 1.5) * 0.5)
        end
    elseif kind == 'abort' then
        if self.plan and self.plan.pid == f[1] then
            self:end_plan('Aborted by ' .. tostring(f[2]) .. ': ' .. tostring(f[3]), true)
        end
    end
end

----------------------------------------------------------------------------
-- execution (every client follows the plan; only the step's member acts)

function coordinator:begin_plan(pid, mob, chain, steps, leader)
    for _, s in ipairs(steps) do
        s.name = s.name or self:ability_name(s.kind, s.id)
        s.delay = self.data.delay(s.kind, s.id)
    end
    local current = self:current_chain(mob)
    self.plan = { pid = pid, mob = mob, chain = chain, steps = steps, index = 1, leader = leader,
        continuing = current ~= nil }
    local text = planner.describe({ steps = steps, chain = chain })
    self.last_plan = text
    local me = self:my_name()
    local involved = false
    for _, s in ipairs(steps) do if s.member == me then involved = true end end
    if self.settings.announce ~= 'off' and (involved or leader == me) then
        self:note('Skillchain:', text)
    end
    if self.settings.announce == 'party' and leader == me then
        self.w.send_command('input /p Skillchain: ' .. text)
    end
    local first_at = self:now()
    if current and current.opens and current.opens > first_at then first_at = current.opens end
    first_at = first_at + (current and (tonumber(self.settings.step_margin) or 0.4) or 0)
    self:arm_step(1, first_at)
end

function coordinator:arm_step(index, at)
    local plan = self.plan
    local step = plan.steps[index]
    plan.deadline = at + (tonumber(self.settings.step_timeout) or 6)
    if step.member ~= self:my_name() then return end
    local pid = plan.pid
    local wait = math.max(0, at - self:now())
    self.env.schedule(function() self:fire(pid, index) end, wait)
end

function coordinator:fire(pid, index, attempt)
    attempt = attempt or 1
    local plan = self.plan
    if not plan or plan.pid ~= pid or plan.index ~= index then return end
    local step = plan.steps[index]
    local ok, why = self:validate_step(plan.mob, step)
    if not ok then
        self:abort(self:my_name() .. ' cannot use ' .. step.name .. ' (' .. tostring(why) .. ')')
        return
    end
    local prefix = step.kind == 'bp' and '/pet' or '/ws'
    self:dbg('Step ' .. index .. ': ' .. step.name .. (attempt > 1 and ' (retry)' or ''))
    self.w.send_command('input ' .. prefix .. ' "' .. step.name .. '" ' .. tostring(plan.mob))
    -- FFXI can refuse input during an action lock ("Unable to use ... at this
    -- time"). If our action has not appeared, try once more while the window
    -- is still open. Inferred: 2s covers the input-to-packet time; confirm live.
    if attempt < 2 then
        self.env.schedule(function() self:fire(pid, index, attempt + 1) end, 2.0)
    end
end

function coordinator:abort(reason)
    if not self.plan then return end
    self:send('abort', self.plan.pid, self:my_name(), reason)
    self:end_plan(reason, true)
end

function coordinator:end_plan(reason, failed)
    local plan = self.plan
    self.plan = nil
    self.last_result = (failed and 'aborted: ' or 'done: ') .. tostring(reason)
    if failed then
        if self.settings.announce ~= 'off' and plan then
            self:note('Skillchain stopped:', reason)
        end
    else
        self:dbg('Plan complete: ' .. tostring(reason))
    end
    self.retry_at = self:now() + 0.3
end

-- Action packet from the game (all clients see party members' actions).
function coordinator:on_action(packet)
    if not self.data or type(packet) ~= 'table' then return end
    local category = tonumber(packet.category)
    if category ~= 3 and category ~= 13 then return end
    local kind = (category == 13) and 'bp' or 'ws'
    local id = tonumber(packet.param)
    if not id or #self.data.props(kind, id) == 0 then return end
    local _, by_id = self:party_map()
    local actor = by_id[packet.actor_id]
    if not actor then return end
    for _, target in ipairs(packet.targets or {}) do
        local action = target.actions and target.actions[1]
        if action then
            local hit = HIT_MESSAGES[tonumber(action.message)] == true
            local add = tonumber(action.add_effect_message)
            local effect = (add and CHAIN_EFFECTS[add]) and add or nil
            if hit then self:record_step(target.id, kind, id, effect) end
            self:check_plan(target.id, actor, kind, id, hit, effect)
        end
    end
end

function coordinator:check_plan(mob_id, actor, kind, id, hit, effect)
    local plan = self.plan
    if not plan or plan.mob ~= mob_id then return end
    local step = plan.steps[plan.index]
    if not (step.member == actor and step.kind == kind and step.id == id) then
        self:end_plan('Unexpected ' .. actor .. ' ' .. self:ability_name(kind, id), true)
        return
    end
    if not hit then
        self:end_plan(actor .. ' ' .. step.name .. ' missed', true)
        return
    end
    local chain = self.chains[mob_id]
    -- Only a fresh plan's opener may land without a skillchain effect.
    if (plan.index > 1 or plan.continuing) and not effect then
        self:end_plan('No skillchain from ' .. step.name, true)
        return
    end
    plan.index = plan.index + 1
    if plan.index > #plan.steps then
        self:end_plan(chain and chain.chain or plan.chain, false)
        return
    end
    local at = self:now() + (step.delay or 3) + (tonumber(self.settings.step_margin) or 0.4)
    self:arm_step(plan.index, at)
end

----------------------------------------------------------------------------
-- periodic work

function coordinator:tick()
    local now = self:now()
    if now - self.last_tick < 0.25 then return end
    self.last_tick = now
    if not self.data then return end

    for mob_id, c in pairs(self.chains) do
        if now >= c.expires then self.chains[mob_id] = nil end
    end

    if self.plan then
        if not self:valid_mob(self.plan.mob) then
            self:end_plan('Target gone', true)
        elseif self.plan.deadline and now > self.plan.deadline then
            self:abort('Step ' .. self.plan.index .. ' (' .. self.plan.steps[self.plan.index].member .. ') timed out')
        end
        return
    end

    if self.poll then
        if now >= self.poll.deadline then
            if self.poll.phase == 'offers' then
                self:finish_offers()
            else
                self:dbg('Acknowledgement timeout')
                self:send('result', self.poll.pid, 'timeout', 'no acknowledgement')
                self.last_result = 'timeout: no acknowledgement'
                self:end_poll('none')
            end
        end
        return
    end

    if not self:can_poll() then return end
    local mob = self:fight_target()
    if not mob then return end
    local offer = self:build_offer(mob)
    if self:offer_has_ready(offer) then
        self:start_poll(mob)
    end
end

function coordinator:reset(reason)
    if self.plan then self:end_plan(reason or 'Reset', true) end
    self.poll = nil
    self.chains = {}
end

----------------------------------------------------------------------------
-- settings and commands

local BOOL_KEYS = { enabled=true, hold_for_three=true, allow_bp=true, mixed=true }
local NUMBER_KEYS = { max_steps=true, hold_max_tp=true, min_tp=true, poll_window=true,
    ack_window=true, step_margin=true, step_timeout=true, retry_delay=true }
local TEXT_KEYS = { targets=true, openers=true, announce=true }

function coordinator:apply_setting(key, value, from_ipc)
    if BOOL_KEYS[key] then
        self.settings[key] = (value == 'true' or value == 'on')
    elseif NUMBER_KEYS[key] then
        local n = tonumber(value)
        if not n then return false end
        self.settings[key] = n
    elseif TEXT_KEYS[key] then
        self.settings[key] = value or ''
    else
        return false
    end
    if key == 'enabled' and not self.settings.enabled then self:reset('Skillchains off') end
    if self.env.save then self.env.save() end
    if from_ipc then self:dbg('Setting ' .. key .. ' = ' .. tostring(self.settings[key]) .. ' (from another client)') end
    return true
end

-- Set locally and on every other Boom client so the whole party plans alike.
function coordinator:set_everywhere(key, value)
    if self:apply_setting(key, value, false) then
        self:send('set', key, tostring(value))
        return true
    end
    return false
end

-- Turn user text into Trust's capitalization: "light" -> "Light", "light lv.4" -> "Light Lv.4".
function coordinator:canonical_target(text)
    local t = text:lower()
    local names = { 'Light Lv.4', 'Darkness Lv.4', 'Radiance', 'Umbra', 'Light', 'Darkness', 'Fusion', 'Fragmentation',
        'Gravitation', 'Distortion', 'Transfixion', 'Compression', 'Liquefaction', 'Scission', 'Reverberation',
        'Detonation', 'Induration', 'Impaction', 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Thunder', 'Water', 'Dark' }
    for _, n in ipairs(names) do
        if n:lower() == t then return n end
    end
    return nil
end

return coordinator
