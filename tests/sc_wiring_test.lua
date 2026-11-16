-- Loads the real Boom.lua with mocked Windower APIs and checks the skillchain
-- wiring: //boom sc commands, setting broadcast, startup and burst coexistence.
--   lua5.1 tests/sc_wiring_test.lua
-- Mocked only; not Windower or FFXI.
local script_dir = (arg[0] or ''):gsub('[^/\\]+$', '')
package.path = script_dir .. '?.lua;' .. script_dir .. '../?.lua;' .. package.path
local env = require('sc_env')
env.install_windower_stubs()

local passed = 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if not ok then error('Test failed: ' .. name .. ' - ' .. tostring(err), 0) end
    passed = passed + 1
    print('PASS ' .. name)
end

local function boot(trust_path)
    for k in pairs(package.loaded) do
        if k:match('^sc/') or k:match('^cylibs/') or k == 'config' then package.loaded[k] = nil end
    end
    local events, chats, commands, ipc, scheduled = {}, {}, {}, {}, {}
    local saved = {}
    local mob = { id = 1234, name = 'Bats', is_npc = true, valid_target = true, hpp = 90, distance = 25 }
    local player = { id = 1, name = 'Cioara', main_job_id = 4, sub_job_id = 5, main_job_level = 20,
        sub_job_level = 10, vitals = { mp = 80, tp = 0 }, buffs = {}, status = 0 }
    package.preload['resources'] = function()
        local spells = { ['Fire'] = { id = 101, en = 'Fire', levels = { [4] = 1 }, mp_cost = 5 } }
        return {
            spells = { with = function(_, _, v) return spells[v] end },
            weapon_skills = {}, job_abilities = { with = function() return nil end },
        }
    end
    package.preload['chat'] = function()
        string.color = function(s, c) return '<' .. c .. '>' .. s .. '</>' end
        return {}
    end
    package.preload['packets'] = function() return {} end
    package.preload['config'] = function()
        return {
            load = function(_, defaults)
                local s = {}
                for k, v in pairs(defaults) do s[k] = v end
                s.trust_path = trust_path
                return s
            end,
            save = function(s, scope) saved[#saved + 1] = scope end,
        }
    end
    _G._addon = {}
    _G.windower = {
        addon_path = '/nowhere/addons/Boom/',
        ffxi = {
            get_player = function() return player end,
            get_spells = function() return { [101] = true } end,
            get_spell_recasts = function() return {} end,
            get_mob_by_target = function(w) if w == 't' then return mob end end,
            get_mob_by_id = function(id) if id == mob.id then return mob end end,
            get_party = function() return { p0 = { name = 'Cioara', mob = { id = 1 } } } end,
            get_abilities = function() return { weapon_skills = {}, job_abilities = {} } end,
            get_ability_recasts = function() return {} end,
            get_info = function() return {} end,
            get_mob_by_index = function() return nil end,
        },
        packets = { parse_action = function(d) return d end },
        register_event = function(name, fn)
            events[name] = events[name] or {}
            table.insert(events[name], fn)
        end,
        add_to_chat = function(_, s) chats[#chats + 1] = s end,
        send_command = function(s) commands[#commands + 1] = s end,
        send_ipc_message = function(s) ipc[#ipc + 1] = s end,
    }
    coroutine.schedule = function(fn) scheduled[#scheduled + 1] = fn end
    dofile(script_dir .. '../Boom.lua')
    local w = { events = events, chats = chats, commands = commands, ipc = ipc, saved = saved,
        scheduled = scheduled, mob = mob }
    function w.emit(name, ...)
        for _, fn in ipairs(events[name] or {}) do fn(...) end
    end
    function w.cmd(...) w.emit('addon command', ...) end
    function w.has(fragment)
        for _, c in ipairs(chats) do if c:find(fragment, 1, true) then return true end end
        return false
    end
    return w
end

check('startup reports skillchains ON when Trust data loads', function()
    local w = boot(env.trust_root())
    assert(w.has('Skillchains '), 'startup line')
    assert(w.has('<0>ON</>'), 'should report ON: ' .. table.concat(w.chats, '\n'))
end)

check('//boom help lists sc; //boom sc help lists options', function()
    local w = boot(env.trust_root())
    w.cmd('help'); assert(w.has(' sc help'))
    w.cmd('sc', 'help'); assert(w.has(' hold on|off')); assert(w.has(' target <list>|clear'))
end)

check('//boom sc target broadcasts canonical names and saves', function()
    local w = boot(env.trust_root())
    w.cmd('sc', 'target', 'light,fusion,Thunder')
    assert(w.ipc[#w.ipc] == 'boomsc|set|targets|Light,Fusion,Thunder', tostring(w.ipc[#w.ipc]))
    assert(w.saved[#w.saved] == 'all', 'saved globally')
    w.cmd('sc', 'target', 'bogus')
    assert(w.has('Unknown target:'))
end)

check('//boom sc opener keeps original capitalisation', function()
    local w = boot(env.trust_root())
    w.cmd('sc', 'opener', 'Cioara:Flaming', 'Crush')
    assert(w.ipc[#w.ipc] == 'boomsc|set|openers|Cioara:Flaming Crush', tostring(w.ipc[#w.ipc]))
end)

check('//boom sc steps, hold, off and status', function()
    local w = boot(env.trust_root())
    w.cmd('sc', 'steps', '2'); assert(w.ipc[#w.ipc] == 'boomsc|set|max_steps|2')
    w.cmd('sc', 'steps', '9'); assert(w.has('Unknown sc command:'))
    w.cmd('sc', 'hold', 'on'); assert(w.ipc[#w.ipc] == 'boomsc|set|hold_for_three|true')
    w.cmd('sc', 'off'); assert(w.ipc[#w.ipc] == 'boomsc|set|enabled|false')
    w.cmd('sc', 'status'); assert(w.has('Trust data:')); assert(w.has('Last plan:'))
    w.cmd('status'); assert(w.has('<167>Skillchains:</> <0>OFF</>'))
end)

check('a setting received over IPC applies locally', function()
    local w = boot(env.trust_root())
    w.emit('ipc message', 'boomsc|set|min_tp|1500')
    w.cmd('sc', 'status'); assert(w.has('Min TP 1500'))
end)

check('bursting still works with the coordinator loaded', function()
    local w = boot(env.trust_root())
    w.emit('incoming chunk', 0x28, { category = 3, actor_id = 99, param = 42,
        targets = { { id = w.mob.id, actions = { { add_effect_message = 295, message = 185, has_add_effect = true } } } } })
    for _, fn in ipairs(w.scheduled) do fn() end
    assert(w.commands[1] == 'input /ma "Fire" <t>', tostring(w.commands[1]))
end)

check('missing Trust data: skillchains off with a reason, bursting unaffected', function()
    local w = boot('/no/such/Trust/')
    assert(w.has('Trust data not found'), table.concat(w.chats, '\n'))
    w.emit('incoming chunk', 0x28, { category = 3, targets = { { id = w.mob.id,
        actions = { { add_effect_message = 295, message = 185 } } } } })
    for _, fn in ipairs(w.scheduled) do fn() end
    assert(w.commands[1] == 'input /ma "Fire" <t>', tostring(w.commands[1]))
    w.cmd('sc', 'status'); assert(w.has('NO DATA'))
end)

print(passed .. ' wiring tests passed')
