-- Boom skillchain coordinator: Windower wiring, settings and //boom sc commands.
-- Loaded by Boom.lua. Burst code in Boom.lua is unaffected if this fails to load.

local trust_data = require('sc/trust_data')
local coordinator = require('sc/coordinator')

local boom_sc = {}

local ui        -- chat helpers from Boom.lua
local settings
local config
local sc         -- coordinator instance
local load_error = nil

local function colored(v, c) return ui.colored(v, c) end

local function default_trust_root()
    local path = (windower.addon_path or ''):gsub('\\', '/')
    -- addons/Boom/ -> addons/Trust/
    local parent = path:gsub('/+$', ''):match('^(.*)/[^/]+$')
    return parent and (parent .. '/Trust/') or ''
end

local function save()
    if config and settings then config.save(settings, 'all') end
end

local function load_data()
    local root = (settings.trust_path ~= nil and settings.trust_path ~= '') and settings.trust_path or default_trust_root()
    local data, err = trust_data.load(root)
    if not data then
        load_error = err
        return nil
    end
    load_error = nil
    return data
end

function boom_sc.init(helpers)
    ui = helpers
    config = require('config')
    settings = config.load('data/sc_settings.xml', coordinator.default_settings)

    local data = load_data()
    sc = coordinator.new({
        windower = windower,
        res = require('resources'),
        data = data,
        settings = settings,
        save = save,
        now = os.clock,
        schedule = function(fn, delay) coroutine.schedule(fn, delay) end,
        chat = { message = ui.message, notice = ui.notice, debug = ui.debug, colored = ui.colored },
        burst_elements = helpers.burst_elements,
    })

    windower.register_event('ipc message', function(message)
        sc:on_ipc(message)
    end)
    windower.register_event('incoming chunk', function(id, data_bytes)
        if id ~= 0x28 then return end
        local ok, packet = pcall(windower.packets.parse_action, data_bytes)
        if ok and packet then sc:on_action(packet) end
    end)
    windower.register_event('incoming text', function(original)
        if type(original) == 'string' and (original:find('was refused. Waiting for readiness.', 1, true)
            or original:find('was unsuccessful. Retrying.', 1, true)) then
            sc.failsafe_at = os.clock()
        end
    end)
    windower.register_event('prerender', function()
        sc:tick()
    end)
    windower.register_event('zone change', function() sc:reset('Zoned') end)
    windower.register_event('logout', function() sc:reset('Logged out') end)
    windower.register_event('job change', function() sc:reset('Job changed') end)

    if not data then
        ui.notice('Skillchains:', 'OFF - Trust data not found (' .. tostring(load_error) .. '). //boom sc trust <folder>')
    end
    return sc
end

function boom_sc.status_line()
    if not sc then return 'not loaded' end
    if not sc.data then return 'Trust data missing' end
    return settings.enabled and 'ON' or 'OFF'
end

local function on_off(value, current)
    if value == 'on' then return true end
    if value == 'off' then return false end
    return not current
end

local function help_line(syntax, description)
    ui.message(colored('//boom sc', 200) .. colored(syntax, 207) .. colored(' -> ', 200) .. colored(description, 0))
end

function boom_sc.help()
    ui.message(colored('Skillchain commands', 167) .. colored(' - settings apply to every Boom client', 0))
    help_line(' status', 'Show skillchain settings and last plan')
    help_line(' on|off', 'Enable or disable coordinated skillchains')
    help_line(' steps 2-6', 'Longest chain to plan (default 3)')
    help_line(' hold on|off', 'Save TP for a 3-step chain when the party can make one')
    help_line(' holdtp <n>', 'Stop holding once a ready member reaches this TP (default 3000)')
    help_line(' target <list>|clear', 'Prefer properties/elements, e.g. Light,Fusion,Fire')
    help_line(' opener <list>|clear', 'Prefer openers, e.g. Savage Blade,Cioara:Flaming Crush')
    help_line(' tp <n>', 'Minimum TP to weapon skill (default 1000)')
    help_line(' solo <n>|off', 'With no chain possible, weapon skill alone at this TP (default 3000)')
    help_line(' bp on|off', 'Include Blood Pact: Rage')
    help_line(' mixed on|off', 'Let one member give a weapon skill and a blood pact')
    help_line(' preferbp on|off', 'Prefer chains that use a blood pact over weapon skills only (on)')
    help_line(' grace <sec>', 'Wait after a continuation window opens before the next step (1)')
    help_line(' announce local|party|off', 'Where to show plans')
    help_line(' set <key> <value>', 'Timing: poll_window, ack_window, step_margin, grace, step_timeout, retry_delay, retry_interval')
    help_line(' set color_member|color_ability|color_chain <n>', 'Plan line colors (207 names, 0 abilities, 158 result)')
    help_line(' trust <folder>', 'Trust addon folder on this client (default ../Trust/)')
end

local function bool_text(v) return ui.state_color(v) end

function boom_sc.status()
    ui.message(colored('Skillchains', 167) .. ' ' .. (sc.data and bool_text(settings.enabled) or colored('NO DATA', 167)) ..
        colored(' | Steps ' .. tostring(settings.max_steps) .. ' | Hold ', 0) .. bool_text(settings.hold_for_three) ..
        colored(' | BP ', 0) .. bool_text(settings.allow_bp ~= false) .. colored(' | Prefer BP ', 0) ..
        bool_text(settings.prefer_bp ~= false) .. colored(' | Grace ' .. tostring(settings.grace) .. 's | Min TP ' .. tostring(settings.min_tp) ..
        ' | Solo ' .. ((tonumber(settings.solo_tp) or 0) > 0 and tostring(settings.solo_tp) or 'off'), 0))
    ui.notice('Targets:', settings.targets ~= '' and settings.targets or 'Any (best available)')
    ui.notice('Openers:', settings.openers ~= '' and settings.openers or 'Any')
    ui.notice('Trust data:', sc.data and tostring(sc.data.root) or tostring(load_error))
    ui.notice('Last plan:', sc.last_plan)
    ui.notice('Last result:', sc.last_result)
    if sc.plan then
        ui.notice('Active:', 'step ' .. sc.plan.index .. ' of ' .. #sc.plan.steps .. ' on mob ' .. tostring(sc.plan.mob))
    end
end

-- args: list of lower-cased words after "sc"; raw: same words with original case
function boom_sc.command(args, raw)
    local cmd = args[1] or 'status'
    local value = args[2]
    local rest = table.concat(raw, ' ', 2)
    if cmd == 'help' then
        boom_sc.help()
    elseif cmd == 'status' then
        boom_sc.status()
    elseif cmd == 'on' or cmd == 'off' then
        sc:set_everywhere('enabled', cmd == 'on' and 'true' or 'false')
        ui.message(colored('Skillchains', 167) .. ' ' .. bool_text(settings.enabled))
    elseif cmd == 'steps' and tonumber(value) and tonumber(value) >= 2 and tonumber(value) <= 6 then
        sc:set_everywhere('max_steps', value)
        ui.notice('Steps:', value)
    elseif cmd == 'hold' then
        sc:set_everywhere('hold_for_three', tostring(on_off(value, settings.hold_for_three)))
        ui.message(colored('Hold for 3 steps', 167) .. ' ' .. bool_text(settings.hold_for_three))
    elseif cmd == 'holdtp' and tonumber(value) then
        sc:set_everywhere('hold_max_tp', value)
        ui.notice('Hold TP cap:', value)
    elseif cmd == 'solo' and (value == 'off' or tonumber(value)) then
        sc:set_everywhere('solo_tp', value == 'off' and '0' or value)
        ui.notice('Solo release:', value == 'off' and 'off' or (value .. ' TP'))
    elseif cmd == 'tp' and tonumber(value) then
        sc:set_everywhere('min_tp', value)
        ui.notice('Minimum TP:', value)
    elseif cmd == 'bp' then
        sc:set_everywhere('allow_bp', tostring(on_off(value, settings.allow_bp ~= false)))
        ui.message(colored('Blood pacts', 167) .. ' ' .. bool_text(settings.allow_bp))
    elseif cmd == 'preferbp' then
        sc:set_everywhere('prefer_bp', tostring(on_off(value, settings.prefer_bp ~= false)))
        ui.message(colored('Prefer blood pacts', 167) .. ' ' .. bool_text(settings.prefer_bp))
    elseif cmd == 'grace' and tonumber(value) and tonumber(value) >= 0 and tonumber(value) <= 4 then
        sc:set_everywhere('grace', value)
        ui.notice('Grace period:', value .. 's after a continuation window opens')
    elseif cmd == 'mixed' then
        sc:set_everywhere('mixed', tostring(on_off(value, settings.mixed ~= false)))
        ui.message(colored('Mixed WS + BP', 167) .. ' ' .. bool_text(settings.mixed))
    elseif cmd == 'announce' and (value == 'local' or value == 'party' or value == 'off') then
        sc:set_everywhere('announce', value)
        ui.notice('Announce:', value)
    elseif cmd == 'target' or cmd == 'targets' then
        if value == nil or value == 'clear' or value == 'any' then
            sc:set_everywhere('targets', '')
            ui.notice('Targets:', 'Any (best available)')
        else
            local list, bad = {}, {}
            for _, item in ipairs(coordinator.split_list(rest)) do
                local name = sc:canonical_target(item)
                if name then list[#list + 1] = name else bad[#bad + 1] = item end
            end
            if #bad > 0 then
                ui.notice('Unknown target:', table.concat(bad, ', '))
            else
                sc:set_everywhere('targets', table.concat(list, ','))
                ui.notice('Targets:', table.concat(list, ', ') .. ' (falls back to best available)')
            end
        end
    elseif cmd == 'opener' or cmd == 'openers' then
        if value == nil or value == 'clear' or value == 'any' then
            sc:set_everywhere('openers', '')
            ui.notice('Openers:', 'Any')
        else
            sc:set_everywhere('openers', rest)
            ui.notice('Openers:', rest .. ' (falls back to any usable opener)')
        end
    elseif cmd == 'set' and value and raw[3] then
        if sc:set_everywhere(value, raw[3]) then
            ui.notice('Set:', value .. ' = ' .. tostring(settings[value]))
        else
            ui.notice('Unknown setting:', value)
        end
    elseif cmd == 'trust' and value then
        settings.trust_path = rest
        save()
        sc.data = load_data()
        ui.notice('Trust data:', sc.data and sc.data.root or tostring(load_error))
    else
        ui.notice('Unknown sc command:', table.concat(raw, ' '))
        boom_sc.help()
    end
end

return boom_sc
