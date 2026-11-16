-- Boom skillchain coordinator: Trust data bridge.
--
-- Loads Trust's own skillchain data instead of copying it:
--   cylibs/res/skills.lua           skillchain properties per weapon skill / blood pact
--   cylibs/util/skillchain_util.lua property combination matrix and levels
-- and exposes them as plain strings and tables, so the planner never touches
-- Trust's L{}/S{} objects and can later move into Trust unchanged.
--
-- The rules below mirror Trust 8f65874 (test/autorun-and-settings-fix):
--   SkillchainBuilder:get_skillchain_by_properties (first match, previous
--   properties outer loop, new ability properties inner loop) and
--   SkillchainStep:is_closed (level >= 4).

local trust_data = {}

local DEFAULT_DELAY = 3 -- SkillchainAbility:get_delay default when skills.lua sets none

local function add_path(root)
    root = root:gsub('\\', '/')
    if root:sub(-1) ~= '/' then root = root .. '/' end
    local entry = root .. '?.lua'
    if not package.path:find(entry, 1, true) then
        package.path = entry .. ';' .. package.path
    end
    return root
end

local function set_names(set)
    local names = {}
    if type(set) ~= 'table' then return names end
    for key, value in pairs(set) do
        local element = (value == true) and key or value
        if type(element) == 'table' and element.get_name then
            names[#names + 1] = element:get_name()
        elseif type(element) == 'string' then
            names[#names + 1] = element
        end
    end
    table.sort(names)
    return names
end

-- trust_root: folder that contains Trust's cylibs/ (e.g. addons/Trust/).
-- Returns adapter or nil, error message.
function trust_data.load(trust_root)
    if type(trust_root) ~= 'string' or trust_root == '' then
        return nil, 'Trust folder not set'
    end
    local norm = trust_root:gsub('\\', '/')
    if norm:sub(-1) ~= '/' then norm = norm .. '/' end
    for _, file in ipairs({ 'cylibs/res/skills.lua', 'cylibs/util/skillchain_util.lua' }) do
        local handle = io.open(norm .. file, 'r')
        if not handle then return nil, 'missing ' .. norm .. file end
        handle:close()
    end
    local root = add_path(norm)
    local ok, err = pcall(function()
        require('sets')
        require('lists')
    end)
    if not ok then return nil, 'Windower sets/lists libraries unavailable: ' .. tostring(err) end

    local ok_skills, skills = pcall(require, 'cylibs/res/skills')
    if not ok_skills or type(skills) ~= 'table' then
        return nil, 'Could not load Trust skills.lua from ' .. root .. ' (' .. tostring(skills) .. ')'
    end
    local ok_util, util = pcall(require, 'cylibs/util/skillchain_util')
    if not ok_util or type(util) ~= 'table' then
        return nil, 'Could not load Trust skillchain_util.lua from ' .. root .. ' (' .. tostring(util) .. ')'
    end
    return trust_data.from_tables(skills, util, root)
end

-- Builds the adapter from already-loaded Trust tables (also used by tests).
function trust_data.from_tables(skills, util, root)
    local adapter = { root = root }

    local function skillchain(name)
        local sc = rawget(util, name)
        if type(sc) == 'table' and type(sc.get_level) == 'function' then return sc end
        return nil
    end

    local function entry(kind, id)
        if kind == 'ws' then return skills.weapon_skills and skills.weapon_skills[id] end
        if kind == 'bp' then return skills.job_abilities and skills.job_abilities[id] end
        return nil
    end

    -- Ordered list of property names for an ability (Trust order preserved).
    function adapter.props(kind, id)
        local e = entry(kind, id)
        local result = {}
        if e and type(e.skillchain) == 'table' then
            for _, name in ipairs(e.skillchain) do
                if skillchain(name) then result[#result + 1] = name end
            end
        end
        return result
    end

    function adapter.name(kind, id)
        local e = entry(kind, id)
        return e and e.en or nil
    end

    function adapter.delay(kind, id)
        local e = entry(kind, id)
        return (e and tonumber(e.delay)) or DEFAULT_DELAY
    end

    -- Skillchain made by property a followed by property b, or nil.
    function adapter.combine(a, b)
        local first = skillchain(a)
        if not first then return nil end
        local result = rawget(first, b)
        if type(result) == 'table' and type(result.get_name) == 'function' then
            return result:get_name()
        end
        return nil
    end

    -- Trust get_skillchain_by_properties: first match over previous x next.
    function adapter.combine_lists(previous, next_props)
        for _, p1 in ipairs(previous) do
            for _, p2 in ipairs(next_props) do
                local made = adapter.combine(p1, p2)
                if made then return made end
            end
        end
        return nil
    end

    function adapter.level(name)
        local sc = skillchain(name)
        return sc and sc:get_level() or 0
    end

    function adapter.elements(name)
        local sc = skillchain(name)
        return sc and set_names(sc:get_elements()) or {}
    end

    function adapter.is_property(name)
        return skillchain(name) ~= nil
    end

    function adapter.is_closed(name)
        return adapter.level(name) >= 4
    end

    -- Every blood pact id Trust knows skillchain properties for.
    function adapter.blood_pact_ids()
        local ids = {}
        for id in pairs(skills.job_abilities or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end

    return adapter
end

return trust_data
