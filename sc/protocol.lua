-- Boom skillchain coordinator: IPC message format (pure; no Windower calls).
--
-- Every message is one line: boomsc|<type>|field|field...
-- Names never contain '|' or ','; abilities travel as numeric resource ids.

local protocol = {}

protocol.PREFIX = 'boomsc'

local function split(text, sep)
    local parts = {}
    local start = 1
    while true do
        local i = text:find(sep, start, true)
        if not i then
            parts[#parts + 1] = text:sub(start)
            break
        end
        parts[#parts + 1] = text:sub(start, i - 1)
        start = i + 1
    end
    return parts
end
protocol.split = split

function protocol.encode(kind, ...)
    local parts = { protocol.PREFIX, kind }
    for i = 1, select('#', ...) do
        local v = select(i, ...)
        parts[#parts + 1] = tostring(v == nil and '' or v)
    end
    return table.concat(parts, '|')
end

-- Returns kind, fields{} or nil when the message is not ours.
function protocol.decode(message)
    if type(message) ~= 'string' then return nil end
    local parts = split(message, '|')
    if parts[1] ~= protocol.PREFIX or not parts[2] then return nil end
    local fields = {}
    for i = 3, #parts do fields[#fields + 1] = parts[i] end
    return parts[2], fields
end

-- Abilities: "w42r,w40n,b550r" (w=weapon skill, b=blood pact; r=ready, n=not ready)
function protocol.encode_abilities(list)
    local out = {}
    for _, a in ipairs(list) do
        out[#out + 1] = (a.kind == 'bp' and 'b' or 'w') .. tostring(a.id) .. (a.ready and 'r' or 'n')
    end
    return table.concat(out, ',')
end

function protocol.decode_abilities(text)
    local list = {}
    if not text or text == '' then return list end
    for _, token in ipairs(split(text, ',')) do
        local k, id, r = token:match('^([wb])(%d+)([rn])$')
        if k then
            list[#list + 1] = { kind = (k == 'b') and 'bp' or 'ws', id = tonumber(id), ready = r == 'r' }
        end
    end
    return list
end

-- Plan steps: "Clairvaux:w42;Cioara:b550"
function protocol.encode_steps(steps)
    local out = {}
    for _, s in ipairs(steps) do
        out[#out + 1] = s.member .. ':' .. (s.kind == 'bp' and 'b' or 'w') .. tostring(s.id)
    end
    return table.concat(out, ';')
end

function protocol.decode_steps(text)
    local steps = {}
    if not text or text == '' then return steps end
    for _, token in ipairs(split(text, ';')) do
        local member, k, id = token:match('^([^:]+):([wb])(%d+)$')
        if member then
            steps[#steps + 1] = { member = member, kind = (k == 'b') and 'bp' or 'ws', id = tonumber(id) }
        end
    end
    return steps
end

-- Poll ids order concurrent polls: earlier second wins, then name, then counter.
function protocol.make_poll_id(time_seconds, name, counter)
    return string.format('%d.%s.%d', time_seconds, name, counter)
end

function protocol.poll_before(a, b)
    local ta, na, ca = a:match('^(%d+)%.(.+)%.(%d+)$')
    local tb, nb, cb = b:match('^(%d+)%.(.+)%.(%d+)$')
    if not ta or not tb then return a < b end
    ta, tb, ca, cb = tonumber(ta), tonumber(tb), tonumber(ca), tonumber(cb)
    if ta ~= tb then return ta < tb end
    if na ~= nb then return na < nb end
    return ca < cb
end

return protocol
