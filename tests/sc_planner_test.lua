-- Offline checks of the skillchain planner and IPC format using Trust's real
-- skills.lua and skillchain_util.lua. Run from the Boom folder:
--   lua5.1 tests/sc_planner_test.lua      (BOOM_TRUST=<Trust folder> to override)
-- These are not FFXI tests: no packets, timing or game rules are exercised.
local script_dir = (arg[0] or ''):gsub('[^/\\]+$', '')
package.path = script_dir .. '?.lua;' .. package.path
local env = require('sc_env')
local data = env.setup()
local planner = require('sc/planner')
local protocol = require('sc/protocol')

local passed = 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if not ok then error('Test failed: ' .. name .. ' - ' .. tostring(err), 0) end
    passed = passed + 1
    print('PASS ' .. name)
end
local function eq(a, b, what) assert(a == b, (what or 'value') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a)) end

-- Weapon skill / blood pact ids from Trust cylibs/res/skills.lua
local WS = { savage = 42, vorpal = 40, fast = 32, wasp = 16, gust = 19, evisc = 25, swift = 41, torcleaver = 59 }
local BP = { flaming = 550, predator = 598 }

local function ws(id, ready) return { kind = 'ws', id = id, ready = ready ~= false } end
local function bp(id, ready) return { kind = 'bp', id = id, ready = ready ~= false } end
local function party()
    return {
        { name = 'Clairvaux', tp = 1200, abilities = { ws(WS.savage), ws(WS.vorpal), ws(WS.fast) } },
        { name = 'Myrr', tp = 1000, abilities = { ws(WS.wasp), ws(WS.gust), ws(WS.evisc) } },
        { name = 'Cioara', tp = 0, abilities = { bp(BP.flaming), bp(BP.predator) } },
    }
end
local function plan(members, options, current)
    return planner.plan({ members = members, options = options, current = current, data = data })
end
local function members_distinct(steps)
    local seen = {}
    for _, s in ipairs(steps) do
        if seen[s.member] then return false end
        seen[s.member] = true
    end
    return true
end

check('Trust data: combination matrix, levels, elements, delays', function()
    eq(data.combine('Fusion', 'Fragmentation'), 'Light', 'Fusion > Fragmentation')
    eq(data.combine('Gravitation', 'Distortion'), 'Darkness', 'Gravitation > Distortion')
    eq(data.combine('Light', 'Light'), 'Light Lv.4', 'Light > Light')
    eq(data.combine('Scission', 'Scission'), nil, 'Scission > Scission')
    eq(data.level('Light'), 3); eq(data.level('Fusion'), 2); eq(data.level('Scission'), 1)
    assert(data.is_closed('Light Lv.4') and data.is_closed('Radiance') and not data.is_closed('Light'))
    eq(table.concat(data.elements('Fusion'), ','), 'Fire,Light')
    eq(table.concat(data.props('ws', WS.savage), ','), 'Fragmentation,Scission')
    eq(table.concat(data.props('bp', BP.flaming), ','), 'Fusion,Reverberation')
    eq(data.delay('ws', WS.savage), 3, 'default delay')
    eq(data.combine_lists({ 'Gravitation', 'Transfixion' }, { 'Fragmentation', 'Scission' }), 'Fragmentation',
        'Trust first-match order')
end)

check('three members make the best available chain, each member once', function()
    local r = plan(party())
    eq(r.action, 'execute'); eq(#r.steps, 3, 'steps'); eq(r.chain, 'Light')
    assert(members_distinct(r.steps), 'a member acted twice')
    eq(planner.describe(r), 'Myrr Evisceration > Clairvaux Savage Blade > Cioara Flaming Crush = Light')
end)

check('plan is deterministic regardless of offer order', function()
    local m = party()
    local a = planner.describe(plan(m))
    local reversed = { m[3], m[2], m[1] }
    eq(planner.describe(plan(reversed)), a, 'reordered offers')
end)

check('impossible target falls back to best chain and says so', function()
    local r = plan(party(), { targets = { 'Darkness' } })
    eq(r.action, 'execute'); eq(r.chain, 'Light')
    assert(r.reason:find('fallback'), r.reason)
end)

check('possible property target beats a higher-level chain', function()
    local r = plan(party(), { targets = { 'Distortion' } })
    eq(r.chain, 'Distortion')
    assert(not r.reason:find('fallback'), r.reason)
end)

check('element target picks a chain carrying that element', function()
    local r = plan(party(), { targets = { 'Earth' } })
    local has = false
    for _, e in ipairs(data.elements(r.chain)) do if e == 'Earth' then has = true end end
    assert(has, 'chain ' .. r.chain .. ' lacks Earth')
end)

check('preferred opener is used when any chain can follow it', function()
    local r = plan(party(), { openers = { { member = 'Myrr', ability = 'Gust Slash' } } })
    eq(r.steps[1].name, 'Gust Slash')
    eq(r.steps[1].member, 'Myrr')
end)

check('impossible opener falls back to any usable opener', function()
    local r = plan(party(), { openers = { { ability = 'Knights of Round' } } })
    eq(r.action, 'execute'); eq(r.chain, 'Light')
end)

check('max steps 2 limits the plan', function()
    local r = plan(party(), { max_steps = 2 })
    eq(#r.steps, 2)
end)

check('not-ready abilities are never executed', function()
    local m = party()
    m[2].abilities = { ws(WS.wasp, false), ws(WS.gust, false), ws(WS.evisc, false) }
    local r = plan(m)
    eq(r.action, 'execute')
    for _, s in ipairs(r.steps) do assert(s.member ~= 'Myrr', 'used an unready member') end
end)

check('hold for three waits when a third member could join', function()
    local m = party()
    m[2].tp = 400
    m[2].abilities = { ws(WS.wasp, false), ws(WS.gust, false), ws(WS.evisc, false) }
    local r = plan(m, { hold_for_three = true })
    eq(r.action, 'hold'); assert(r.reason:find('3 steps'), r.reason)
end)

check('hold is ignored when the party cannot make 3 steps', function()
    local m = {
        { name = 'Clairvaux', tp = 1200, abilities = { ws(WS.savage) } },
        { name = 'Cioara', tp = 0, abilities = { bp(BP.flaming) } },
    }
    local r = plan(m, { hold_for_three = true })
    eq(r.action, 'execute'); eq(#r.steps, 2)
end)

check('hold stops at the TP cap', function()
    local m = party()
    m[1].tp = 3000
    m[2].abilities = { ws(WS.wasp, false), ws(WS.gust, false), ws(WS.evisc, false) }
    local r = plan(m, { hold_for_three = true })
    eq(r.action, 'execute')
end)

check('continues an open chain from the current window', function()
    local m = { { name = 'Clairvaux', tp = 1000, abilities = { ws(WS.savage) } } }
    local r = plan(m, nil, { step = 2, chain = 'Fusion' })
    eq(r.action, 'execute'); eq(#r.steps, 1); eq(r.chain, 'Light'); assert(r.continuing)
end)

check('an open chain that is already the target is not continued off target', function()
    local m = { { name = 'Cioara', tp = 0, abilities = { bp(BP.flaming) } } }
    local r = plan(m, { targets = { 'Distortion' } }, { step = 2, chain = 'Distortion' })
    eq(r.action, 'none'); assert(r.reason:find('Keeping'), r.reason)
    local free = plan(m, nil, { step = 2, chain = 'Distortion' })
    eq(free.action, 'execute'); eq(free.chain, 'Fusion')
end)

check('a single ready member with no partner does not open', function()
    local m = { { name = 'Clairvaux', tp = 1000, abilities = { ws(WS.savage) } } }
    eq(plan(m).action, 'none')
end)

check('closed chain restarts from an opener', function()
    local r = plan(party(), nil, { step = 4, chain = 'Light Lv.4' })
    eq(r.action, 'execute'); assert(not r.continuing)
end)

check('blood pacts off removes them', function()
    local r = plan(party(), { allow_bp = false })
    for _, s in ipairs(r.steps) do assert(s.kind ~= 'bp', 'used a blood pact') end
end)

check('mixed lets one member give a WS and a BP; off forbids it', function()
    local m = {
        { name = 'Cioara', tp = 1000, abilities = { ws(WS.savage), bp(BP.flaming) } },
        { name = 'Clairvaux', tp = 1000, abilities = { ws(WS.evisc) } },
    }
    local on = plan(m, { mixed = true })
    eq(#on.steps, 3, 'mixed on'); eq(on.chain, 'Light')
    local off = plan(m, { mixed = false })
    eq(#off.steps, 2, 'mixed off')
    assert(members_distinct(off.steps))
end)

check('protocol round-trips abilities, steps and messages', function()
    local text = protocol.encode_abilities({ ws(42), bp(550, false) })
    eq(text, 'w42r,b550n')
    local back = protocol.decode_abilities(text)
    eq(back[2].kind, 'bp'); eq(back[2].id, 550); eq(back[2].ready, false)
    local steps = protocol.decode_steps(protocol.encode_steps({ { member = 'Myrr', kind = 'ws', id = 25 },
        { member = 'Cioara', kind = 'bp', id = 550 } }))
    eq(steps[2].member, 'Cioara'); eq(steps[2].kind, 'bp')
    local kind, f = protocol.decode(protocol.encode('offer', 'p1', 'Myrr', 1000, 'w42r'))
    eq(kind, 'offer'); eq(f[2], 'Myrr'); eq(f[4], 'w42r')
    eq(protocol.decode('party_chat hello'), nil, 'foreign IPC ignored')
end)

check('concurrent polls order by time, then name, then counter', function()
    assert(protocol.poll_before('100.Myrr.5', '101.Clairvaux.1'))
    assert(protocol.poll_before('100.Clairvaux.9', '100.Myrr.1'))
    assert(protocol.poll_before('100.Myrr.1', '100.Myrr.2'))
    assert(not protocol.poll_before('100.Myrr.2', '100.Myrr.1'))
end)

print(passed .. ' planner tests passed')
