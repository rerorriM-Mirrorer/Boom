-- Multi-client simulation of the skillchain coordinator. Several coordinator
-- instances share a fake IPC bus and a fake game that turns /ws and /pet
-- commands into action packets, using Trust's real data for chain results.
--   lua5.1 tests/sc_coordinator_test.lua
-- Simulated only: real FFXI timing, packets, latency and refusals are untested.
local script_dir = (arg[0] or ''):gsub('[^/\\]+$', '')
package.path = script_dir .. '?.lua;' .. package.path
local env = require('sc_env')
local data = env.setup()
local coordinator = require('sc/coordinator')

local passed = 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if not ok then error('Test failed: ' .. name .. ' - ' .. tostring(err), 0) end
    passed = passed + 1
    print('PASS ' .. name)
end
local function eq(a, b, what) assert(a == b, (what or 'value') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a)) end

-- Resources the coordinator reads (names, weapon skill range, BP recast id).
local res = {
    weapon_skills = {}, job_abilities = {},
}
for id, e in pairs(require('cylibs/res/skills').weapon_skills) do
    res.weapon_skills[id] = { id = id, en = e.en, range = 2, targets = { Enemy = true } }
end
for id, e in pairs(require('cylibs/res/skills').job_abilities) do
    res.job_abilities[id] = { id = id, en = e.en }
end
res.job_abilities[603] = { id = 603, en = 'Blood Pact: Rage', recast_id = 173 }
function res.job_abilities:with(key, value)
    for _, v in pairs(self) do if type(v) == 'table' and v[key] == value then return v end end
end
local ws_by_name, ja_by_name = {}, {}
for id, v in pairs(res.weapon_skills) do ws_by_name[v.en] = id end
for id, v in pairs(res.job_abilities) do if type(v) == 'table' then ja_by_name[v.en] = id end end

local effect_for = {}
for id, name in pairs(coordinator.CHAIN_EFFECTS) do
    if not effect_for[name] or id < effect_for[name] then effect_for[name] = id end
end
effect_for['Light Lv.4'] = effect_for['Light']; effect_for['Darkness Lv.4'] = effect_for['Darkness']

----------------------------------------------------------------------------
-- world

local World = {}
World.__index = World

function World.new()
    local w = setmetatable({ t = 100, tasks = {}, clients = {}, by_name = {}, party = {},
        mob = { id = 9001, index = 101, name = 'Training Dummy', is_npc = true, valid_target = true,
            hpp = 100, distance = 9, model_size = 2 },
        chain = nil, commands = {}, log = {}, swallow = {} }, World)
    return w
end

function World:at(delay, fn)
    self.tasks[#self.tasks + 1] = { at = self.t + delay, fn = fn, seq = #self.tasks }
end

function World:advance(seconds, step)
    step = step or 0.05
    local stop = self.t + seconds
    while self.t < stop - 1e-9 do
        self.t = self.t + step
        local due = {}
        local keep = {}
        for _, task in ipairs(self.tasks) do
            if task.at <= self.t + 1e-9 then due[#due + 1] = task else keep[#keep + 1] = task end
        end
        self.tasks = keep
        table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
        for _, task in ipairs(due) do task.fn() end
        for _, c in ipairs(self.clients) do c.sc:tick() end
    end
end

-- Game: resolve a weapon skill / blood pact and broadcast the action packet.
function World:perform(client, kind, id, target_id)
    local actor = client
    if self.swallow[client.name] then
        self.log[#self.log + 1] = client.name .. ' refused'
        return
    end
    local begin_actor = kind == 'bp' and actor.pet.id or actor.player.id
    self:at(0.1, function()
        local packet = { category = 7, param = 24931, actor_id = begin_actor, targets = { { id = target_id, actions = { {} } } } }
        for _, other in ipairs(self.clients) do other.sc:on_action(packet) end
        if kind == 'bp' then actor.recasts[173] = 60 end -- recast starts at the command, before the pact lands
    end)
    self:at(kind == 'bp' and 3.0 or 1.0, function()
        local props = data.props(kind, id)
        local effect = nil
        local now = self.t
        local c = self.chain
        if c and now >= c.opens and now < c.expires then
            local prev = c.chain and { c.chain } or c.props
            local made = data.combine_lists(prev, props)
            if made then
                local chain = made
                effect = effect_for[made]
                self.chain = { chain = chain, props = props, step = c.step + 1,
                    opens = now + data.delay(kind, id), expires = now + data.delay(kind, id) + 8 - (c.step + 1) }
            else
                self.chain = nil
            end
        end
        if not effect then
            self.chain = { chain = nil, props = props, step = 1, opens = now + data.delay(kind, id),
                expires = now + data.delay(kind, id) + 7 }
        end
        if kind == 'ws' then actor.player.vitals.tp = 0 else actor.recasts[173] = 60 end
        self.log[#self.log + 1] = string.format('%.2f %s %s%s', now, actor.name, data.name(kind, id),
            effect and (' -> ' .. coordinator.CHAIN_EFFECTS[effect]) or '')
        local packet = {
            category = kind == 'bp' and 13 or 3, param = id,
            actor_id = kind == 'bp' and actor.pet.id or actor.player.id,
            targets = { { id = target_id, actions = { { message = kind == 'bp' and 317 or 185,
                add_effect_message = effect, has_add_effect = effect ~= nil } } } },
        }
        for _, other in ipairs(self.clients) do other.sc:on_action(packet) end
    end)
end

function World:add_client(name, opts)
    opts = opts or {}
    local world = self
    local n = #self.clients + 1
    local client = { name = name, recasts = { [173] = 0 }, chats = {} }
    client.player = { id = 1000 + n, index = 10 + n, name = name, status = opts.engaged == false and 0 or 1,
        vitals = { tp = opts.tp or 0 }, buffs = {} }
    client.me = { id = client.player.id, index = client.player.index, model_size = 1 }
    if opts.pet then client.pet = { id = 5000 + n, index = 500 + n, name = 'Ifrit' } end
    client.ws = opts.ws or {}
    client.burst = opts.burst
    client.bp = opts.bp or {}
    client.in_party = opts.in_party ~= false
    if client.in_party then
        self.party[#self.party + 1] = client
    end

    local fake = { ffxi = {} }
    function fake.ffxi.get_player() return client.player end
    function fake.ffxi.get_party()
        local p = {}
        if not client.in_party then
            p.p0 = { name = name, mob = { id = client.player.id, pet_index = client.pet and client.pet.index } }
            return p
        end
        for i, member in ipairs(world.party) do
            p['p' .. (i - 1)] = { name = member.name,
                mob = { id = member.player.id, pet_index = member.pet and member.pet.index } }
        end
        return p
    end
    function fake.ffxi.get_mob_by_id(id)
        if id == world.mob.id then return world.mob end
        for _, c in ipairs(world.clients) do if c.player.id == id then return c.me end end
    end
    function fake.ffxi.get_mob_by_index(index)
        for _, c in ipairs(world.clients) do if c.pet and c.pet.index == index then return c.pet end end
    end
    function fake.ffxi.get_mob_by_target(which)
        if which == 'pet' then return client.pet end
        if (which == 't' or which == 'bt') and world.mob.hpp > 0 then return world.mob end
    end
    function fake.ffxi.get_abilities()
        local ws, ja = {}, {}
        for _, n2 in ipairs(client.ws) do ws[#ws + 1] = ws_by_name[n2] end
        for _, n2 in ipairs(client.bp) do ja[#ja + 1] = ja_by_name[n2] end
        return { weapon_skills = ws, job_abilities = ja }
    end
    function fake.ffxi.get_ability_recasts() return client.recasts end
    function fake.ffxi.get_info() return { mog_house = false } end
    function fake.send_ipc_message(message)
        for _, other in ipairs(world.clients) do
            if other ~= client then
                world:at(0.02, function() other.sc:on_ipc(message) end)
            end
        end
    end
    function fake.send_command(command)
        world.commands[#world.commands + 1] = name .. ': ' .. command
        local prefix, ability, target = command:match('^input (/%a+) "(.-)" (%d+)$')
        if prefix == '/ws' then
            world:perform(client, 'ws', ws_by_name[ability], tonumber(target))
        elseif prefix == '/pet' then
            world:perform(client, 'bp', ja_by_name[ability], tonumber(target))
        end
    end

    local settings = {}
    for k, v in pairs(coordinator.default_settings) do settings[k] = v end
    for k, v in pairs(opts.settings or {}) do settings[k] = v end
    client.settings = settings
    client.sc = coordinator.new({
        windower = fake, res = res, data = data, settings = settings,
        now = function() return world.t end,
        schedule = function(fn, delay) world:at(delay, fn) end,
        burst_elements = function() return client.burst or {} end,
        chat = {
            message = function(t) client.chats[#client.chats + 1] = t end,
            notice = function(h, t) client.chats[#client.chats + 1] = h .. ' ' .. t end,
            debug = function(t) client.chats[#client.chats + 1] = 'DEBUG ' .. t end,
            colored = function(v) return tostring(v) end,
        },
    })
    self.clients[#self.clients + 1] = client
    self.by_name[name] = client
    return client
end

local function standard_party(opts)
    opts = opts or {}
    local w = World.new()
    w:add_client('Clairvaux', { tp = 1200, ws = { 'Savage Blade', 'Vorpal Blade', 'Fast Blade' }, settings = opts.settings })
    w:add_client('Myrr', { tp = opts.myrr_tp or 1000, ws = { 'Wasp Sting', 'Gust Slash', 'Evisceration' }, settings = opts.settings })
    w:add_client('Cioara', { tp = 0, engaged = false, pet = true, bp = { 'Flaming Crush', 'Predator Claws' },
        settings = opts.settings, burst = opts.cioara_burst })
    return w
end

local function count(list, pattern)
    local n = 0
    for _, v in ipairs(list) do if v:find(pattern) then n = n + 1 end end
    return n
end

local function game_actions(w)
    local n = 0
    for _, line in ipairs(w.log) do if not line:find('refused') then n = n + 1 end end
    return n
end

----------------------------------------------------------------------------

check('three clients poll, agree and execute one 3-step Light chain in order', function()
    local w = standard_party()
    w:advance(15)
    eq(#w.commands, 3, 'commands sent: ' .. table.concat(w.commands, ' | '))
    eq(w.commands[1], 'Myrr: input /ws "Evisceration" 9001')
    eq(w.commands[2], 'Clairvaux: input /ws "Savage Blade" 9001')
    eq(w.commands[3], 'Cioara: input /pet "Flaming Crush" 9001')
    assert(w.log[#w.log]:find('-> Light'), 'last action should make Light: ' .. w.log[#w.log])
    for _, c in ipairs(w.clients) do
        eq(c.sc.plan, nil, c.name .. ' still has a plan')
        assert(c.sc.last_result:find('Light'), c.name .. ' result ' .. c.sc.last_result)
    end
end)

check('later steps wait for the previous action plus the chain delay', function()
    local w = standard_party()
    w:advance(15)
    local times = {}
    for _, line in ipairs(w.log) do times[#times + 1] = tonumber(line:match('^(%S+)')) end
    eq(#times, 3)
    assert(times[2] - times[1] >= 3.0 + 0.4, 'step 2 too early: ' .. (times[2] - times[1]))
    assert(times[3] - times[2] >= 3.0 + 0.4, 'step 3 too early: ' .. (times[3] - times[2]))
    assert(times[3] - times[2] < 7.5, 'step 3 too late (blood pact lands ~3s after input)')
end)

check('simultaneous readiness on every client still yields exactly one plan', function()
    local w = standard_party()
    -- all clients tick at the same instant in the first advance step
    w:advance(15, 0.25)
    eq(#w.commands, 3, table.concat(w.commands, ' | '))
    eq(count(w.commands, 'Evisceration'), 1, 'duplicate opener')
end)

check('a member refusing at acknowledgement stops the plan before any action', function()
    local w = standard_party()
    -- Myrr's TP drops between offer and ack: drop it when the plan arrives
    local myrr = w.by_name['Myrr']
    local original = myrr.sc.on_ipc
    myrr.sc.on_ipc = function(self, message)
        if message:find('^boomsc|plan') then myrr.player.vitals.tp = 200 end
        return original(self, message)
    end
    w:advance(1.5)
    eq(#w.commands, 0, table.concat(w.commands, ' | '))
    local leader
    for _, c in ipairs(w.clients) do if c.sc.last_result:find('refused') then leader = c end end
    assert(leader, 'no client recorded the refusal')
end)

check('a refused game action times out and frees every client', function()
    local w = standard_party()
    w.swallow['Clairvaux'] = true -- step 2 is input but the game never performs it
    w:advance(12.5)
    eq(game_actions(w), 1, 'only the opener happened')
    assert(count(w.commands, 'Clairvaux: input /ws') >= 3, 'Clairvaux should keep retrying: ' .. table.concat(w.commands, ' | '))
    for _, c in ipairs(w.clients) do
        eq(c.sc.plan, nil, c.name .. ' stuck in plan')
        assert(c.sc.last_result:find('timed out'), c.name .. ': ' .. c.sc.last_result)
    end
end)

check('a retry recovers a step the game refused once', function()
    local w = standard_party()
    local clairvaux = w.by_name['Clairvaux']
    local refusals = 0
    local perform = w.perform
    w.perform = function(self, client, kind, id, target)
        if client == clairvaux and refusals == 0 then
            refusals = 1
            self.log[#self.log + 1] = 'Clairvaux refused'
            return
        end
        return perform(self, client, kind, id, target)
    end
    w:advance(18)
    eq(game_actions(w), 3, table.concat(w.log, ' | '))
    assert(w.log[#w.log]:find('-> Light'), w.log[#w.log])
end)

check('an unexpected party weapon skill aborts the plan everywhere', function()
    local w = standard_party()
    w:advance(1.6) -- opener has been input
    -- Cioara (step 3) acts early with Predator Claws, out of turn
    w:perform(w.by_name['Cioara'], 'bp', 598, w.mob.id)
    w:advance(3.4) -- blood pacts land ~3s after input
    for _, c in ipairs(w.clients) do
        eq(c.sc.plan, nil, c.name .. ' kept the plan')
        assert(c.sc.last_result:find('Unexpected') or c.sc.last_result:find('No skillchain'), c.name .. ': ' .. c.sc.last_result)
    end
end)

check('settings set on one client reach every client', function()
    local w = standard_party()
    w.by_name['Myrr'].sc:set_everywhere('targets', 'Distortion')
    w.by_name['Myrr'].sc:set_everywhere('max_steps', '2')
    w:advance(0.1)
    for _, c in ipairs(w.clients) do
        eq(c.settings.targets, 'Distortion', c.name)
        eq(c.settings.max_steps, 2, c.name)
    end
end)

check('targets follow the shared setting and fall back when impossible', function()
    local w = standard_party({ settings = { targets = 'Distortion' } })
    w:advance(15)
    assert(w.log[#w.log]:find('Distortion'), w.log[#w.log])
    local w2 = standard_party({ settings = { targets = 'Umbra' } })
    w2:advance(15)
    assert(w2.log[#w2.log]:find('Light'), 'fallback chain: ' .. w2.log[#w2.log])
end)

check('hold for three waits for TP, then runs the 3-step chain', function()
    local w = standard_party({ myrr_tp = 500, settings = { hold_for_three = true } })
    w:advance(5)
    eq(#w.commands, 0, 'should hold: ' .. table.concat(w.commands, ' | '))
    w.by_name['Myrr'].player.vitals.tp = 1000
    w:advance(15)
    eq(#w.commands, 3, table.concat(w.commands, ' | '))
end)

check('Boom clients outside the party are ignored', function()
    local w = standard_party()
    w:add_client('Mule', { tp = 2000, ws = { 'Savage Blade' }, in_party = false })
    w:advance(15)
    eq(count(w.commands, '^Mule'), 0, 'outsider acted')
    eq(#w.commands, 3)
end)

check('scales to six members and uses at most max steps', function()
    local w = standard_party({ settings = { max_steps = 4 } })
    w:add_client('Ichi', { tp = 1000, ws = { 'Swift Blade' }, settings = { max_steps = 4 } })
    w:add_client('Ni', { tp = 1000, ws = { 'Gust Slash' }, settings = { max_steps = 4 } })
    w:add_client('San', { tp = 1000, ws = { 'Fast Blade' }, settings = { max_steps = 4 } })
    w:advance(25)
    assert(#w.commands >= 3 and #w.commands <= 4, '#commands ' .. #w.commands .. ': ' .. table.concat(w.commands, ' | '))
    eq(game_actions(w), #w.commands)
    local seen = {}
    for _, line in ipairs(w.commands) do
        local who = line:match('^(%S+):')
        assert(not seen[who], who .. ' acted twice')
        seen[who] = true
    end
end)

check('off on one client turns coordination off on all', function()
    local w = standard_party()
    w.by_name['Cioara'].sc:set_everywhere('enabled', 'false')
    w:advance(10)
    eq(#w.commands, 0)
end)

check('target death clears the plan', function()
    local w = standard_party()
    w:advance(1.6)
    w.mob.hpp = 0
    w:advance(1)
    for _, c in ipairs(w.clients) do eq(c.sc.plan, nil, c.name) end
end)

check('Shield Bash (category 3 job ability, id 46 = Expiacion) is not a weapon skill', function()
    local w = standard_party()
    w:advance(1.6) -- opener input, plan active
    local clairvaux = w.by_name['Clairvaux']
    local packet = { category = 3, param = 46, actor_id = clairvaux.player.id,
        targets = { { id = w.mob.id, actions = { { message = 110 } } } } }
    for _, c in ipairs(w.clients) do c.sc:on_action(packet) end
    for _, c in ipairs(w.clients) do
        assert(c.sc.plan ~= nil, c.name .. ' dropped the plan: ' .. c.sc.last_result)
    end
    w:advance(14)
    eq(#w.commands, 3, table.concat(w.commands, ' | '))
    assert(w.log[#w.log]:find('-> Light'), w.log[#w.log])
end)

check('a slow blood pact is not cancelled by its own recast', function()
    local w = World.new()
    w:add_client('Cioara', { tp = 0, engaged = false, pet = true, bp = { 'Flaming Crush' } })
    w:add_client('Clairvaux', { tp = 1000, ws = { 'Savage Blade' } })
    w:advance(12)
    eq(count(w.commands, '/pet'), 1, table.concat(w.commands, ' | '))
    assert(w.log[#w.log]:find('-> Light'), table.concat(w.log, ' | '))
    for _, c in ipairs(w.clients) do
        assert(count(c.chats, 'Skillchain stopped') == 0, c.name .. ' stopped the plan: ' .. table.concat(c.chats, ' | '))
    end
end)

check('a busy member keeps re-sending until the game accepts', function()
    local w = standard_party()
    local myrr = w.by_name['Myrr']
    local refusals = 0
    local perform = w.perform
    w.perform = function(self, client, kind, id, target)
        if client == myrr and refusals < 3 then
            refusals = refusals + 1
            self.log[#self.log + 1] = 'Myrr refused'
            return
        end
        return perform(self, client, kind, id, target)
    end
    w:advance(20)
    eq(refusals, 3)
    assert(w.log[#w.log]:find('-> Light'), table.concat(w.log, ' | '))
end)

check('lone melee at 3000 TP releases when no chain is possible', function()
    local w = World.new()
    w:add_client('Clairvaux', { tp = 3000, ws = { 'Savage Blade' } })
    w:add_client('Myrr', { tp = 200, ws = { 'Wasp Sting' } })
    w:advance(3)
    eq(#w.commands, 1, table.concat(w.commands, ' | '))
    eq(w.commands[1], 'Clairvaux: input /ws "Savage Blade" 9001')
    w:advance(3)
    eq(w.by_name['Myrr'].sc.plan, nil)
    assert(w.by_name['Clairvaux'].sc.last_result:find('done'), w.by_name['Clairvaux'].sc.last_result)
end)

check('below the solo TP nothing fires alone; solo off never releases', function()
    local w = World.new()
    w:add_client('Clairvaux', { tp = 2900, ws = { 'Savage Blade' } })
    w:advance(5)
    eq(#w.commands, 0)
    local w2 = World.new()
    w2:add_client('Clairvaux', { tp = 3000, ws = { 'Savage Blade' }, settings = { solo_tp = 0 } })
    w2:advance(5)
    eq(#w2.commands, 0)
end)

check('plan line colors character, ability and result differently', function()
    local w = World.new()
    local c = w:add_client('Clairvaux', { tp = 1000, ws = { 'Savage Blade' } })
    c.sc.env.chat.colored = function(v, color) return '<' .. color .. '>' .. tostring(v) .. '</>' end
    local line = c.sc:colored_plan({ { member = 'Cioara', name = 'Poison Nails' }, { member = 'Clairvaux', name = 'Fast Blade' } }, 'Distortion')
    eq(line, '<167>Skillchain:</> <207>Cioara</> <0>Poison Nails</><0> > </><207>Clairvaux</> <0>Fast Blade</><0> = </><158>Distortion</>')
    c.settings.color_member = 5
    assert(c.sc:colored_plan({ { member = 'Myrr', name = 'Brainshaker' } }, nil):find('<5>Myrr</>.*<158> %(solo%)</>'))
end)

check('a step waits once for Failsafe before re-sending', function()
    local w = standard_party()
    local myrr = w.by_name['Myrr']
    local perform = w.perform
    local refused = false
    w.perform = function(self, client, kind, id, target)
        if client == myrr and not refused then
            refused = true
            myrr.sc.failsafe_at = w.t -- Failsafe announced it will re-send
            return
        end
        return perform(self, client, kind, id, target)
    end
    w:advance(1.2)
    eq(count(w.commands, '^Myrr'), 1, 'Myrr re-sent too early: ' .. table.concat(w.commands, ' | '))
    w:advance(18)
    assert(count(w.commands, '^Myrr') >= 2, 'Myrr never re-sent')
    assert(w.log[#w.log]:find('-> Light'), table.concat(w.log, ' | '))
end)

local function landing_times(w)
    local times = {}
    for _, line in ipairs(w.log) do times[#times + 1] = tonumber(line:match('^(%S+)')) end
    return times
end

check('grace period: a continuation fires 1s after its window opens; grace 0 restores the 0.4s margin', function()
    local w = standard_party()
    w:advance(20)
    local t = landing_times(w)
    eq(#t, 3, table.concat(w.log, ' | '))
    -- weapon skills land ~1s after input in the simulation: 3s delay + 1s grace + 1s
    assert(t[2] - t[1] >= 4.95 and t[2] - t[1] < 5.2, 'step 2 gap ' .. (t[2] - t[1]))
    local w0 = standard_party({ settings = { grace = 0 } })
    w0:advance(20)
    local t0 = landing_times(w0)
    assert(t0[2] - t0[1] < 4.6, 'grace 0 gap ' .. (t0[2] - t0[1]))
end)

check('a long grace is capped so a blood pact still lands before the window closes', function()
    local w = standard_party({ settings = { grace = 3 } })
    w:advance(25)
    assert(w.log[#w.log] and w.log[#w.log]:find('Flaming Crush %-> Light'), table.concat(w.log, ' | '))
end)

check('Blood Pact: Rage is kept for the burst after a chain the avatar can burst', function()
    local w = standard_party({ cioara_burst = { 'Thunder' } }) -- Fragmentation bursts with Thunder/Wind
    w:advance(20)
    for i = 2, #w.log do
        assert(not (w.log[i]:find('Cioara') and w.log[i - 1]:find('-> Fragmentation', 1, true)),
            'pact used right after a burstable chain: ' .. table.concat(w.log, ' | '))
    end
    assert(w.log[#w.log]:find('-> Light'), table.concat(w.log, ' | '))
    -- a burst element that doesn't fit the chain leaves the plan as before
    local w2 = standard_party({ cioara_burst = { 'Fire' } })
    w2:advance(20)
    eq(#w2.log, 3, table.concat(w2.log, ' | '))
end)

check('AoE weapon skills are never used by default; allow_aoe and the list control them', function()
    -- Only an AoE weapon skill: nothing fires, not even a solo release.
    local w = World.new()
    w:add_client('Clairvaux', { tp = 3000, ws = { 'Circle Blade' } })
    w:advance(5)
    eq(#w.commands, 0, table.concat(w.commands, ' | '))
    -- With a single-target one available, that one is used instead.
    local w2 = World.new()
    w2:add_client('Clairvaux', { tp = 3000, ws = { 'Circle Blade', 'Savage Blade' } })
    w2:advance(5)
    eq(w2.commands[1], 'Clairvaux: input /ws "Savage Blade" 9001')
    -- allow_aoe on: the AoE weapon skill may be used.
    local w3 = World.new()
    w3:add_client('Clairvaux', { tp = 3000, ws = { 'Circle Blade' }, settings = { allow_aoe = true } })
    w3:advance(5)
    eq(w3.commands[1], 'Clairvaux: input /ws "Circle Blade" 9001')
    -- Taken off the list: usable while AoE stays off. Name match is exact (Steel Cyclone is not Cyclone).
    local w4 = World.new()
    local c = w4:add_client('Clairvaux', { tp = 3000, ws = { 'Circle Blade' }, settings = { aoe_ws = 'Cyclone' } })
    w4:advance(5)
    eq(w4.commands[1], 'Clairvaux: input /ws "Circle Blade" 9001')
    eq(c.sc:is_aoe_ws(ws_by_name['Steel Cyclone']), false, 'Steel Cyclone')
    eq(c.sc:is_aoe_ws(ws_by_name['Cyclone']), true, 'Cyclone')
    eq(c.sc:canonical_ws('circle blade'), 'Circle Blade')
end)

check('allow_aoe and aoe_ws are shared settings', function()
    local w = standard_party()
    w.by_name['Clairvaux'].sc:set_everywhere('allow_aoe', 'true')
    w.by_name['Clairvaux'].sc:set_everywhere('aoe_ws', 'Cyclone,Shockwave')
    w:advance(0.1)
    for _, c in ipairs(w.clients) do
        eq(c.settings.allow_aoe, true, c.name .. ' allow_aoe')
        eq(c.settings.aoe_ws, 'Cyclone,Shockwave', c.name .. ' aoe_ws')
    end
end)

print(passed .. ' coordinator simulation tests passed')
