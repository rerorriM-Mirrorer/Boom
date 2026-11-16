-- Offline test environment for the skillchain coordinator (LuaJIT or Lua 5.1).
-- Windower's own sets/lists libraries need Windower's patched parser, so these
-- minimal stand-ins provide only what Trust's skills.lua/skillchain_util.lua use
-- at load time: S{...} builds a key=true set, L{...} keeps a plain array.
local env = {}

function env.install_windower_stubs()
    package.loaded['sets'] = package.loaded['sets'] or (function()
        S = function(t) local s = {}; for _, v in ipairs(t or {}) do s[v] = true end; return s end
        return {}
    end)()
    package.loaded['lists'] = package.loaded['lists'] or (function()
        L = function(t) return t or {} end
        return {}
    end)()
end

-- Trust checkout to read data from: BOOM_TRUST env var, else the sibling clone.
function env.trust_root()
    return os.getenv('BOOM_TRUST') or '/home/claude/rerorrim-mirrorer/trust'
end

function env.boom_root()
    return os.getenv('BOOM_ROOT') or '.'
end

function env.setup()
    local root = env.boom_root()
    package.path = root .. '/?.lua;' .. package.path
    env.install_windower_stubs()
    local data, err = require('sc/trust_data').load(env.trust_root())
    assert(data, err)
    return data
end

return env
