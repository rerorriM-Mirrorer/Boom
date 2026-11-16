-- Runs with texlua. These are mocked Windower calls, not in-game tests.
local events = {}
local fake_time = 100
os.clock = function() return fake_time end
local commands, chats, jobs = {}, {}, {}
local scheduled = {}
local known, recasts = {}, {}
local target_id = 1234
local mob = {id = 1234, name = 'Seeker Bats', is_npc = true, valid_target = true, hpp = 98, distance = 25}
local player = {id = 1000, main_job_id = 4, sub_job_id = 5, main_job_level = 20, sub_job_level = 10, vitals = {mp = 80}, buffs={}}
local spells = {
    ['Fire'] = {id=101,en='Fire',levels={[4]=1},mp_cost=5},
    ['Fire II'] = {id=102,en='Fire II',levels={[4]=12},mp_cost=25},
    ['Fire III'] = {id=103,en='Fire III',levels={[4]=26},mp_cost=50},
    ['Thunder'] = {id=104,en='Thunder',levels={[4]=5},mp_cost=6},
    ['Blizzard'] = {id=111,en='Blizzard',levels={[4]=1},mp_cost=6},
    ['Thunder VI'] = {id=105,en='Thunder VI',levels={[4]=100},mp_cost=55},
    ['Stone'] = {id=106,en='Stone',levels={[4]=1},mp_cost=5},
    ['Banish'] = {id=107,en='Banish',levels={[5]=5,[3]=5},mp_cost=10},
    ['Holy'] = {id=108,en='Holy',levels={[3]=50},mp_cost=30},
    ['Holy II'] = {id=109,en='Holy II',levels={[3]=95},mp_cost=85},
    ['Banish II'] = {id=110,en='Banish II',levels={[3]=40},mp_cost=20},
}
for _, spell in pairs(spells) do known[spell.id]=true end
package.preload['resources'] = function()
    return {spells = {with=function(self,key,value) assert(key=='en'); return spells[value] end}}
end
package.preload['packets'] = function() return {} end
package.preload['chat'] = function()
    string.color = function(str, color) return '<color'..color..'>'..str..'</color>' end
    return {}
end
_G._addon = {}
_G.windower = {
    ffxi={
        get_player=function() return player end,
        get_spells=function() return known end,
        get_spell_recasts=function() return recasts end,
        get_mob_by_target=function(which)
            if which == 't' and target_id == mob.id then return mob end
            if which == 'bt' and target_id == -1 then return mob end
            return nil
        end,
        get_mob_by_id=function(id) if id==mob.id then return mob end end,
    },
    packets={parse_action=function(data) return data end},
    register_event=function(ev, fn) events[ev] = fn end,
    add_to_chat=function(channel, s) table.insert(chats, {channel=channel, text=s}) end,
    send_command=function(s) table.insert(commands, s) end,
}
coroutine.schedule = function(fn, delay)
    assert(delay == 0.9, 'working burst delay changed: '..tostring(delay))
    table.insert(scheduled, fn)
end
local function fire(id, effect, category, message_id)
    events['incoming chunk'](0x28, {category=category or 3,targets={{id=id,actions={{add_effect_message=effect,message=message_id or 185,has_add_effect=effect~=nil}}}}})
end
local function chats_contain(fragment)
    for _, entry in ipairs(chats) do
        if entry.text:find(fragment,1,true) then return true end
    end
    return false
end
local function run_pending()
    local tasks = scheduled
    scheduled = {}
    for _,task in ipairs(tasks) do task() end
end
local function reset()
    fake_time = fake_time + 5
    events['zone change']()
    target_id = mob.id; mob.hpp=98; player.buffs={}; player.vitals.mp=80
    recasts={}; commands={}; scheduled={}
    player.main_job_id = 4; player.sub_job_id = 5
    player.main_job_level = 20; player.sub_job_level = 10
    events['addon command']('on')
    events['addon command']('debug','off')
    events['addon command']('trace','off')
    chats = {}
end
local function check(n, f)
    local ok, err = pcall(f)
    if not ok then error('Test failed: '..n..' - '..tostring(err)) end
    print('PASS '..n)
end

local script_dir = (arg[0] or ''):gsub('[^/\\]+$', '')
dofile(script_dir..'../Boom.lua')
check('auto enabled and correct highest learned usable spell', function()
    fire(mob.id, 295);run_pending()
    assert(commands[1] == 'input /ma "Fire II" <t>', tostring(commands[1]))
end)
check('fallback when recast', function()
    reset(); recasts[102]=15;fire(mob.id,295);run_pending()
    assert(commands[1] == 'input /ma "Fire" <t>',tostring(commands[1]))
end)
check('job-level gate including JP spells', function()
    reset();fire(mob.id,288);run_pending()
    assert(commands[1] == 'input /ma "Thunder" <t>',tostring(commands[1]))
end)
check('MP fallback instead of failed expensive nuke', function()
    reset();player.vitals.mp=10;fire(mob.id,295);run_pending()
    assert(commands[1] == 'input /ma "Fire" <t>',tostring(commands[1]))
end)
check('WHM with Holy casts Holy on Light', function()
    reset(); player.main_job_id=3; player.main_job_level=60
    fire(mob.id,288);run_pending()
    assert(commands[1] == 'input /ma "Holy" <t>',tostring(commands[1]))
end)
check('WHM/BLM prioritizes Holy over Thunder on Light', function()
    reset(); player.main_job_id=3; player.main_job_level=60
    player.sub_job_id=4; player.sub_job_level=20
    fire(mob.id,288);run_pending()
    assert(commands[1] == 'input /ma "Holy" <t>',tostring(commands[1]))
end)
check('WHM uses learned Holy II if ready and affordable', function()
    reset(); player.main_job_id=3; player.main_job_level=99
    player.vitals.mp=150
    fire(mob.id,288);run_pending()
    assert(commands[1] == 'input /ma "Holy II" <t>',tostring(commands[1]))
end)
check('WHM Holy fallback to Banish when Holy unavailable', function()
    reset(); player.main_job_id=3; player.main_job_level=60
    recasts[108]=1
    fire(mob.id,288);run_pending()
    assert(commands[1] == 'input /ma "Banish II" <t>',tostring(commands[1]))
end)
check('WHM Holy also bursts Fusion and Transfixion', function()
    reset(); player.main_job_id=3; player.main_job_level=60
    fire(mob.id,293);run_pending()
    assert(commands[1] == 'input /ma "Holy" <t>',tostring(commands[1]))
    reset(); player.main_job_id=3; player.main_job_level=60
    fire(mob.id,298);run_pending()
    assert(commands[1] == 'input /ma "Holy" <t>',tostring(commands[1]))
end)
check('Boom commands renamed and restart uses new addon', function()
    reset(); events['addon command']('restart')
    assert(commands[1] == 'lua reload Boom',tostring(commands[1]))
    reset(); events['addon command']('unload')
    assert(commands[1] == 'lua unload Boom',tostring(commands[1]))
end)
check('no target switching and no wrong-target casts', function()
    reset();target_id=500;fire(mob.id,295);run_pending()
    assert(#commands==0)
end)
check('battle target fallback', function()
    reset();target_id=-1;fire(mob.id,295);run_pending()
    assert(commands[1] == 'input /ma "Fire II" <bt>',tostring(commands[1]))
end)
check('off disables automatic casts', function()
    reset();events['addon command']('off');fire(mob.id,295);run_pending()
    assert(#scheduled==0 and #commands==0)
end)
check('zone cancels queued cast and remains auto-on', function()
    reset();fire(mob.id,295);events['zone change']();run_pending()
    assert(#commands==0)
    fire(mob.id,295);run_pending()
    assert(commands[1] == 'input /ma "Fire II" <t>')
end)
check('unavailable/dying enemy is ignored', function()
    reset();mob.hpp=0;fire(mob.id,295);run_pending()
    assert(#commands==0)
end)
check('disabling status prevents cast', function()
    reset();player.buffs={6};fire(mob.id,295);run_pending()
    assert(#commands==0)
end)
check('skillchain packet parse failure stays nonfatal', function()
    reset();events['incoming chunk'](0x28, {targets={}})
    assert(#commands == 0)
end)
check('all four level 2 skillchain effects are recognized', function()
    local cases = {{290,'Stone'},{291,'Thunder'},{292,'Blizzard'},{293,'Fire II'}}
    for _, c in ipairs(cases) do
        reset(); fire(mob.id,c[1]);run_pending()
        assert(commands[1] and commands[1]:find('"'..c[2]..'"',1,true),tostring(commands[1]))
    end
end)
check('level 2 alternate healing-effect IDs are also recognized', function()
    local cases = {{387,'Stone'},{388,'Thunder'},{389,'Blizzard'},{390,'Fire II'}}
    for _, c in ipairs(cases) do
        reset(); fire(mob.id,c[1]);run_pending()
        assert(commands[1] and commands[1]:find('"'..c[2]..'"',1,true),tostring(commands[1]))
    end
end)
check('primary-message skillchain fallback', function()
    reset(); events['addon command']('debug','on')
    fire(mob.id,nil,3,290);run_pending()
    assert(commands[1] == 'input /ma "Stone" <t>')
    assert(chats_contain('primary action message'))
end)
check('duplicate filter suppresses retransmit but not a later same-effect chain', function()
    reset(); events['addon command']('debug','on')
    fire(mob.id,293);run_pending()
    fake_time = fake_time + 0.10
    fire(mob.id,293);run_pending()
    assert(#commands == 1 and chats_contain('Duplicate packet ignored'))
    fake_time = fake_time + 0.25
    fire(mob.id,293);run_pending()
    assert(#commands == 2, 'later matching effect should be processed')
end)
check('debug reports WS without matching chain and status stores last packet', function()
    reset();events['addon command']('debug','on')
    fire(mob.id,nil,3,185)
    assert(chats_contain('without a recognized chain'))
    events['addon command']('status')
    assert(chats_contain('Last WS:') and chats_contain('action 185'))
    assert(#commands == 0)
end)
check('trace reports non-WS action message IDs on watched target', function()
    reset();events['addon command']('trace','on')
    fire(mob.id,nil,4,2)
    assert(chats_contain('Trace:') and chats_contain('category 4'))
    assert(#commands == 0)
end)
check('no trace message for different target', function()
    reset();events['addon command']('trace','on')
    fire(9999,nil,3,185)
    assert(not chats_contain('No recognized chain'))
end)
check('debug reports pre-dispatch dead target and target mismatch', function()
    reset(); events['addon command']('debug','on');mob.hpp=0
    fire(mob.id,293)
    assert(chats_contain('invalid, or defeated'))
    reset(); events['addon command']('debug','on'); target_id=9999
    fire(mob.id,293)
    assert(chats_contain('not the selected enemy'))
end)
check('all messages and help use WORKFLOW chat formatting', function()
    reset();events['addon command']('help')
    assert(chats_contain('<color200>[Boom]</color>'))
    assert(chats_contain('<color200>//boom</color>'))
    assert(chats_contain('<color207> debug on|off</color>'))
    assert(chats_contain('<color200> -> </color>'))
    events['addon command']('debug','on')
    assert(chats_contain('<color158>ON</color>'))
    events['addon command']('off')
    assert(chats_contain('<color167>OFF</color>'))
    for _,entry in ipairs(chats) do
        assert(entry.channel == 0, 'all message channel must be zero')
        assert(entry.text:find('<color200>[Boom]</color>',1,true), 'missing colored label')
        assert(not entry.text:find('–',1,true) and not entry.text:find('—',1,true))
    end
end)
check('debug details are yellow, while normal values and trace stay white', function()
    reset();events['addon command']('debug','on')
    fire(mob.id, 292)
    assert(chats_contain('<color167>Debug:</color> <color207>Distortion detected'),
        'recognized skillchain debug body should use readable yellow 207')
    reset();events['addon command']('debug','on')
    fire(mob.id, nil, 3, 185)
    assert(chats_contain('<color167>Debug:</color> <color207>WS/pet action'),
        'non-skillchain diagnostic should also be yellow')
    reset();events['addon command']('debug','on')
    mob.hpp=0;fire(mob.id,293)
    assert(chats_contain('<color167>Debug:</color> <color207>Fusion: Mob missing'),
        'skip reason carried by debug should also be yellow')
    reset();events['addon command']('trace','on')
    fire(mob.id, nil, 4, 2)
    assert(chats_contain('<color167>Trace:</color> <color0>No recognized chain'),
        'trace should retain normal white body')
    reset();events['addon command']('status')
    assert(chats_contain('<color167>Skillchain:</color> <color0>'),
        'ordinary status values should remain white')
end)
check('normal restart and unload are single-dispatch with notifications', function()
    reset();events['addon command']('restart'); assert(#commands==1 and commands[1]=='lua reload Boom')
    assert(chats_contain('Reloading Boom'))
    reset();events['addon command']('unload'); assert(#commands==1 and commands[1]=='lua unload Boom')
    assert(chats_contain('Unloading Boom'))
end)
print('All mock tests passed')
