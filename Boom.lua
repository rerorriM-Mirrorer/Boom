-- Boom: an intentionally small, load-and-burst Windower 4 addon.
-- First test version. No automatic target changes or pet commands.
_addon.name = 'Boom'
_addon.author = 'A'
_addon.version = '0.1.3-test4'
_addon.commands = {'boom'}
_addon.windower = '4'

local res = require('resources')
require('chat')
require('packets')

local active = true
local debug_enabled = false
local trace_enabled = false
local sequence = 0
local last_event = {}
local last_action = 'None'
local last_skip = 'None'
local last_skillchain = 'None'
local last_ws_packet = 'None'

-- Only suppress a replay of the same effect on the same mob within a
-- small fraction of a second. Whole-second os.time() comparisons used to
-- swallow legitimate repeated skillchains for almost two seconds.
local duplicate_window = 0.20

-- Element sets follow FFXI magic-burst properties; order is a preference,
-- not a claim about the target's resistances or the strongest possible damage.
local chains = {
    [288] = { 'Light',      {'Thunder', 'Wind', 'Fire', 'Light'} },
    [289] = { 'Darkness',   {'Ice', 'Water', 'Earth', 'Dark'} },
    [290] = { 'Gravitation',{'Earth', 'Dark'} },
    [291] = { 'Fragmentation', {'Thunder', 'Wind'} },
    [292] = { 'Distortion',{'Ice', 'Water'} },
    [293] = { 'Fusion',    {'Fire', 'Light'} },
    [294] = { 'Compression',{'Dark'} },
    [295] = { 'Liquefaction',{'Fire'} },
    [296] = { 'Induration',{'Ice'} },
    [297] = { 'Reverberation',{'Water'} },
    [298] = { 'Transfixion',{'Light'} },
    [299] = { 'Scission',  {'Earth'} },
    [300] = { 'Detonation',{'Wind'} },
    [301] = { 'Impaction', {'Thunder'} },
    [385] = { 'Light',      {'Thunder', 'Wind', 'Fire', 'Light'} },
    [386] = { 'Darkness',   {'Ice', 'Water', 'Earth', 'Dark'} },
    [387] = { 'Gravitation',{'Earth', 'Dark'} },
    [388] = { 'Fragmentation', {'Thunder', 'Wind'} },
    [389] = { 'Distortion',{'Ice', 'Water'} },
    [390] = { 'Fusion',    {'Fire', 'Light'} },
    [391] = { 'Compression',{'Dark'} },
    [392] = { 'Liquefaction',{'Fire'} },
    [393] = { 'Induration',{'Ice'} },
    [394] = { 'Reverberation',{'Water'} },
    [395] = { 'Transfixion',{'Light'} },
    [396] = { 'Scission',  {'Earth'} },
    [397] = { 'Detonation',{'Wind'} },
    [398] = { 'Impaction', {'Thunder'} },
    [767] = { 'Radiance',  {'Thunder', 'Wind', 'Fire', 'Light'} },
    [769] = { 'Radiance',  {'Thunder', 'Wind', 'Fire', 'Light'} },
    [768] = { 'Umbra',     {'Ice', 'Water', 'Earth', 'Dark'} },
    [770] = { 'Umbra',     {'Ice', 'Water', 'Earth', 'Dark'} },
}

local spell_bases = {
    Thunder = 'Thunder', Ice = 'Blizzard', Wind = 'Aero',
    Fire = 'Fire', Water = 'Water', Earth = 'Stone',
}
local tiers = { 'VI', 'V', 'IV', 'III', 'II', '' }

-- Follow the shared FFXI WORKFLOW.md chat convention, including help output:
-- label 200, headings 167, command prefix/arrows 200, syntax 207, text 0.
-- Use ASCII punctuation; typographic dashes are not reliable in FFXI chat.
local function colored(value, color)
    return string.color(tostring(value), color)
end
local function message(body)
    windower.add_to_chat(0, colored('[Boom]', 200)..' '..body)
end
local function notice(heading, body)
    message(colored(heading, 167)..' '..colored(body, 0))
end
-- User-preferred readable yellow for diagnostic details. Keep the standard
-- [Boom] label and heading colors from WORKFLOW.md.
local function debug(text)
    if debug_enabled then
        message(colored('Debug:', 167)..' '..colored(text, 207))
    end
end
local function trace(text)
    if trace_enabled then notice('Trace:', text) end
end
local function state_color(enabled)
    return colored(enabled and 'ON' or 'OFF', enabled and 158 or 167)
end
local function skip(reason)
    last_skip = reason
    debug(reason)
end

local function disabled(player)
    local blocked = {
        [0] = true, [2] = true, [6] = true, [7] = true,
        [10] = true, [14] = true, [17] = true, [28] = true,
        [29] = true, [193] = true, [262] = true,
    }
    for _, buff in ipairs(player.buffs or {}) do
        if blocked[buff] then return true end
    end
    return false
end

local function job_can_cast(spell, player)
    local levels = spell.levels or {}
    local main_level = levels[player.main_job_id]
    local sub_level = levels[player.sub_job_id]
    -- Spell levels above 99 denote job-point unlocks in Windower resources.
    -- Learned spell state is also required for these; level 99 main only.
    local main_ok = (main_level and ((main_level <= 99 and main_level <= player.main_job_level)
        or (main_level > 99 and player.main_job_level >= 99)))
    local sub_ok = sub_level and sub_level <= 99 and sub_level <= player.sub_job_level
    return main_ok or sub_ok
end

local function spell_usable(name, player, known, recasts)
    local spell = res.spells:with('en', name)
    if not spell or not known[spell.id] or not job_can_cast(spell, player) then
        return nil
    end
    if (recasts[spell.id] or 0) > 0 then return nil end
    if (spell.mp_cost or 0) > (player.vitals and player.vitals.mp or 0) then return nil end
    return spell
end

local function candidates(element)
    local result = {}
    local base = spell_bases[element]
    if base then
        for _, suffix in ipairs(tiers) do
            result[#result + 1] = base .. (suffix ~= '' and (' '..suffix) or '')
        end
    elseif element == 'Light' then
        result = {'Holy II', 'Holy', 'Banish III', 'Banish II', 'Banish'}
    elseif element == 'Dark' then
        result = {'Drain III', 'Drain II', 'Drain'}
    end
    return result
end

local function pick_spell(chain, player)
    local known = windower.ffxi.get_spells() or {}
    local recasts = windower.ffxi.get_spell_recasts() or {}
    local elements = chain[2]
    -- WHM prefers Holy/Banish on Light-compatible chains, even with a
    -- nuking subjob. Other jobs keep the established elemental priority.
    if player.main_job_id == 3 then  -- WHM
        for _, element in ipairs(chain[2]) do
            if element == 'Light' then
                elements = {'Light'}
                for _, other in ipairs(chain[2]) do
                    if other ~= 'Light' then
                        elements[#elements + 1] = other
                    end
                end
                break
            end
        end
    end
    for _, element in ipairs(elements) do
        for _, name in ipairs(candidates(element)) do
            local spell = spell_usable(name, player, known, recasts)
            if spell then return spell end
        end
    end
    return nil
end

local function get_matching_target(target_id)
    local current = windower.ffxi.get_mob_by_target('t')
    if current and current.id == target_id then return '<t>' end
    local battle = windower.ffxi.get_mob_by_target('bt')
    if battle and battle.id == target_id then return '<bt>' end
    return nil
end

local function try_burst(token, target_id, chain)
    if not active or token ~= sequence then return end
    local player = windower.ffxi.get_player()
    local target = windower.ffxi.get_mob_by_id(target_id)
    if not player or not target or not target.valid_target or not target.is_npc
        or (target.hpp or 0) <= 0 then
        skip(chain[1]..': Target unavailable at cast time (mob '..tostring(target_id)..')')
        return
    end
    local target_token = get_matching_target(target_id)
    if not target_token then
        skip(chain[1]..': Target mismatch at cast time (mob '..tostring(target_id)..')')
        return
    end
    if target.distance and math.sqrt(target.distance) > 20 then
        skip(chain[1]..': Target more than 20 yalms away')
        return
    end
    if disabled(player) then
        skip(chain[1]..': Character unable to cast')
        return
    end
    local spell = pick_spell(chain, player)
    if not spell then
        last_skip = chain[1]..': No learned, job-usable, ready, affordable matching spell'
        notice('Skipped:', last_skip)
        return
    end
    -- No targeting injection. The verified <t> or <bt> is resolved at dispatch.
    -- Input starts one cast; FFXI/GearSwap remains responsible for completion.
    last_action = chain[1]..' -> '..spell.en..' on '..target.name
    last_skip = 'None'
    message(colored('Casting', 167)..' '..colored(spell.en, 207)..colored(' on '..target.name..' ('..chain[1]..')', 0))
    windower.send_command('input /ma "'..spell.en..'" '..target_token)
end

local function consider_skillchain(mob_id, effect_id)
    if not active then return end
    local chain = chains[effect_id]
    if not chain then
        debug('Unrecognized skillchain effect ID '..tostring(effect_id)..' on mob '..tostring(mob_id))
        return
    end
    last_skillchain = chain[1]..' (ID '..tostring(effect_id)..', mob '..tostring(mob_id)..')'
    local mob = windower.ffxi.get_mob_by_id(mob_id)
    if not mob or not mob.is_npc or not mob.valid_target or (mob.hpp or 0) <= 0 then
        skip(chain[1]..': Mob missing, invalid, or defeated (ID '..tostring(mob_id)..')')
        return
    end
    -- Keep the working rule: only the already-selected target or <bt>.
    if not get_matching_target(mob_id) then
        skip(chain[1]..': Skillchain on '..mob.name..', not the selected enemy')
        return
    end
    local key = tostring(mob_id)..':'..tostring(effect_id)
    local now = os.clock()
    local previous = last_event[key]
    if previous and now >= previous and now - previous < duplicate_window then
        debug(chain[1]..': Duplicate packet ignored (effect '..tostring(effect_id)..')')
        return
    end
    last_event[key] = now
    sequence = sequence + 1
    local token = sequence
    debug(chain[1]..' detected on '..mob.name..' (effect '..tostring(effect_id)..'); cast queued at +0.9s')
    coroutine.schedule(function()
        try_burst(token, mob_id, chain)
    end, 0.9)
end

-- Other addons observe skillchain results in additional-effect message IDs.
-- A recognized main action message is also accepted if the additional-effect
-- field is absent; trace output distinguishes both sources for live checking.
local relevant_action_categories = { [3]=true, [4]=true, [6]=true, [11]=true, [13]=true, [14]=true, [20]=true }
local ws_action_categories = { [3]=true, [13]=true }
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x28 or not active then return end
    local ok, packet = pcall(windower.packets.parse_action, data)
    if not ok or not packet or type(packet.targets) ~= 'table' then
        debug('Unable to parse incoming action packet 0x028')
        return
    end
    for _, target in ipairs(packet.targets) do
        if target and target.id then
            local observed_target = nil
            local is_watched = false
            local category = tonumber(packet.category)
            if relevant_action_categories[category] and
                (trace_enabled or debug_enabled or ws_action_categories[category]) then
                is_watched = get_matching_target(target.id) ~= nil
                if is_watched then
                    observed_target = windower.ffxi.get_mob_by_id(target.id)
                end
            end
            for _, action in ipairs(target.actions or {}) do
                local add_id = tonumber(action.add_effect_message)
                local main_id = tonumber(action.message)
                local effect_id = chains[add_id] and add_id or (chains[main_id] and main_id or nil)
                local detail = 'category '..tostring(category)..', action '..tostring(main_id or 'nil')..
                    ', additional '..tostring(add_id or 'nil')..', has_add '..tostring(action.has_add_effect)
                if is_watched and ws_action_categories[category] then
                    last_ws_packet = detail..', mob '..tostring(target.id)
                end
                if effect_id then
                    if effect_id == main_id and effect_id ~= add_id then
                        debug('Skillchain effect '..effect_id..' found in primary action message, not additional effect')
                    end
                    consider_skillchain(target.id, effect_id)
                elseif is_watched and (trace_enabled or debug_enabled and ws_action_categories[category]) then
                    if ws_action_categories[category] then
                        last_skip = 'Selected-target WS/pet action had no recognized chain ('..detail..')'
                    end
                    if trace_enabled then
                        trace('No recognized chain on '..(observed_target and observed_target.name or tostring(target.id))..': '..detail)
                    elseif ws_action_categories[category] then
                        debug('WS/pet action on selected target without a recognized chain ('..detail..')')
                    end
                end
            end
        end
    end
end)

local function help_line(syntax, description)
    message(colored('//boom', 200)..colored(syntax, 207)..colored(' -> ', 200)..colored(description, 0))
end
local function show_help()
    message(colored('Commands', 167)..colored(' - Auto bursting begins on load', 0))
    help_line(' help', 'Show commands')
    help_line(' status', 'Show state and latest skillchain/WS observation')
    help_line(' on|off', 'Enable or disable automatic bursting')
    help_line(' debug on|off', 'Explain skillchain and casting decisions')
    help_line(' trace on|off', 'Show matching-target action message IDs for missed windows')
    help_line(' restart', 'Reload Boom')
    help_line(' unload', 'Unload Boom')
end
local function show_status()
    message(colored('Status', 167)..' '..colored('v'.._addon.version, 0)..
        colored(' | Auto ', 0)..state_color(active)..colored(' | Debug ', 0)..state_color(debug_enabled)..
        colored(' | Trace ', 0)..state_color(trace_enabled))
    notice('Target:', '<t>/<bt> only | Delay: 0.9s | Duplicate filter: 0.20s')
    notice('Skillchain:', last_skillchain)
    notice('Last WS:', last_ws_packet)
    notice('Last cast:', last_action)
    notice('Last skip:', last_skip)
end

windower.register_event('addon command', function(command, value)
    command = command and command:lower() or 'help'
    value = value and value:lower() or nil
    if command == 'on' or command == 'off' then
        active = command == 'on'
        sequence = sequence + 1
        message(colored('Auto', 167)..' '..state_color(active))
    elseif command == 'status' then
        show_status()
    elseif command == 'debug' or command == 'trace' then
        if command == 'debug' then
            debug_enabled = value == 'on' or (value ~= 'off' and not debug_enabled)
            message(colored('Debug', 167)..' '..state_color(debug_enabled))
        else
            trace_enabled = value == 'on' or (value ~= 'off' and not trace_enabled)
            message(colored('Trace', 167)..' '..state_color(trace_enabled))
        end
    elseif command == 'restart' then
        notice('Restart:', 'Reloading Boom')
        windower.send_command('lua reload Boom')
    elseif command == 'unload' then
        notice('Unload:', 'Unloading Boom')
        windower.send_command('lua unload Boom')
    else
        if command ~= 'help' then notice('Unknown command:', command) end
        show_help()
    end
end)

windower.register_event('zone change', function()
    sequence = sequence + 1
    last_event = {}
end)
windower.register_event('logout', function()
    sequence = sequence + 1
    last_event = {}
end)
windower.register_event('job change', function()
    sequence = sequence + 1
end)

message(colored('Auto', 167)..' '..state_color(active)..colored(' - Loaded; watching skillchains', 0))
