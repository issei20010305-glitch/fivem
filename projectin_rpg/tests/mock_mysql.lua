--[[ oxmysql のインメモリモック (projectin_rpg が発行するクエリのみ対応) ]]
local T = { characters = {}, holdings = {}, definitions = {}, templates = {}, events = {}, claims = {}, audit = {}, history = {}, players = {} }
MOCK.db = T
local ids = { definitions = 0, templates = 0, events = 0 }

local function has(q, s) return q:find(s, 1, true) ~= nil end
local function copy(r) if not r then return nil end local o = {} for k, v in pairs(r) do o[k] = v end return o end

local function exec(q, p)
    p = p or {}
    q = q:gsub('%s+', ' ')
    if q:find('^ ?CREATE TABLE') then return true end
    -- rpg_characters
    if has(q, 'SELECT COUNT(*) FROM rpg_characters') then return T.characters[p[1]] and 1 or 0 end
    if has(q, 'FROM rpg_characters WHERE citizenid') then return copy(T.characters[p[1]]) end
    if has(q, 'INSERT IGNORE INTO rpg_characters') then
        if not T.characters[p[1]] then T.characters[p[1]] = { citizenid = p[1], inventory = p[2], overflow = p[3], stats = p[4] } return 1 end
        return 0
    end
    if has(q, 'UPDATE rpg_characters SET role = ?, role_set_at = ? WHERE citizenid = ? AND role IS NULL') then
        local r = T.characters[p[3]]
        if r and r.role == nil then r.role = p[1] r.role_set_at = p[2] return 1 end
        return 0
    end
    if has(q, 'UPDATE rpg_characters SET role = ?') then local r = T.characters[p[3]] if r then r.role = p[1] return 1 end return 0 end
    if has(q, 'UPDATE rpg_characters SET inventory = ?, overflow = ?') then local r = T.characters[p[3]] if r then r.inventory = p[1] r.overflow = p[2] return 1 end return 0 end
    if has(q, 'UPDATE rpg_characters SET stats') then local r = T.characters[p[2]] if r then r.stats = p[1] end return 1 end
    if has(q, 'FROM players WHERE citizenid') then
        if has(q, 'COUNT') then return T.players[p[1]] and 1 or 0 end
        return T.players[p[1]] and { charinfo = json.encode(T.players[p[1]]) } or nil
    end
    -- rpg_holdings
    if has(q, 'SELECT COUNT(*) FROM rpg_holdings') then return T.holdings[p[1]] and 1 or 0 end
    if has(q, 'SELECT * FROM rpg_holdings') then return copy(T.holdings[p[1]]) end
    if has(q, 'INSERT INTO rpg_holdings') then
        if T.holdings[p[1]] then error('duplicate holding') end
        T.holdings[p[1]] = { citizenid = p[1], run_id = p[2], return_pos = p[3], health = p[4], armour = p[5], snapshot = p[6] }
        return 1
    end
    if has(q, 'DELETE FROM rpg_holdings') then T.holdings[p[1]] = nil return 1 end
    -- rpg_definitions
    if has(q, 'SELECT COUNT(*) FROM rpg_definitions') then local n = 0 for _ in pairs(T.definitions) do n = n + 1 end return n end
    if has(q, 'INSERT INTO rpg_definitions (name, type, status, draft_data, published_data') then
        ids.definitions = ids.definitions + 1
        T.definitions[ids.definitions] = { id = ids.definitions, name = p[1], type = p[2], status = 'published', draft_data = p[3], published_data = p[4], version = 1, has_unpublished = 0 }
        return ids.definitions
    end
    if has(q, 'INSERT INTO rpg_definitions') then
        ids.definitions = ids.definitions + 1
        T.definitions[ids.definitions] = { id = ids.definitions, name = p[1], type = p[2], status = p[3], draft_data = p[4], version = 0, has_unpublished = 1 }
        return ids.definitions
    end
    if has(q, 'SELECT published_data FROM rpg_definitions') then
        local r = T.definitions[p[1]]
        if r and r.status == p[2] then return { published_data = r.published_data } end
        return nil
    end
    if has(q, 'SELECT * FROM rpg_definitions WHERE id') then return copy(T.definitions[p[1]]) end
    if has(q, 'FROM rpg_definitions WHERE status <>') then
        local out = {}
        for _, r in pairs(T.definitions) do if r.status ~= p[1] then out[#out + 1] = copy(r) end end
        table.sort(out, function(a, b) return a.id < b.id end)
        return out
    end
    if has(q, 'UPDATE rpg_definitions SET draft_data') then
        local r = T.definitions[p[5]]
        if not r then return 0 end
        r.draft_data, r.name, r.type, r.has_unpublished = p[1], p[2], p[3], 1
        return 1
    end
    if has(q, 'UPDATE rpg_definitions SET published_data') then
        local r = T.definitions[p[5]]
        r.published_data, r.status, r.version, r.has_unpublished, r.name, r.type = p[1], 'published', r.version + 1, 0, p[2], p[3]
        return 1
    end
    if has(q, "UPDATE rpg_definitions SET status = 'archived'") then T.definitions[p[2]].status = 'archived' return 1 end
    -- rpg_templates
    if has(q, 'SELECT COUNT(*) FROM rpg_templates') then local n = 0 for _ in pairs(T.templates) do n = n + 1 end return n end
    if has(q, 'INSERT INTO rpg_templates') then
        ids.templates = ids.templates + 1
        T.templates[ids.templates] = { id = ids.templates, kind = p[1], name = p[2], data = p[3], created_by = p[4] }
        return ids.templates
    end
    if has(q, 'FROM rpg_templates WHERE id = ?') then local r = T.templates[p[1]] if r and r.kind == 'definition' then return copy(r) end return nil end
    if has(q, 'FROM rpg_templates') then
        local out = {}
        for _, r in pairs(T.templates) do if not has(q, 'WHERE kind') or r.kind == p[1] then out[#out + 1] = copy(r) end end
        table.sort(out, function(a, b) return a.id < b.id end)
        return out
    end
    if has(q, 'DELETE FROM rpg_templates') then T.templates[p[1]] = nil return 1 end
    -- rpg_events
    if has(q, 'INSERT INTO rpg_events') then
        ids.events = ids.events + 1
        T.events[ids.events] = { id = ids.events, definition_id = p[1], name = p[2], type = p[3], location_label = p[4], announce_at = p[5], start_at = p[6], end_at = p[7], status = 'scheduled', announcement = p[8], reminders_sent = '' }
        return ids.events
    end
    if has(q, "FROM rpg_events WHERE status IN") then
        local out = {}
        for _, r in pairs(T.events) do if r.status == 'scheduled' or r.status == 'announced' or r.status == 'active' then out[#out + 1] = copy(r) end end
        return out
    end
    if has(q, 'SELECT COUNT(*) FROM rpg_events WHERE definition_id') then
        local n = 0
        for _, r in pairs(T.events) do if r.definition_id == p[1] and (r.status == 'scheduled' or r.status == 'announced' or r.status == 'active') then n = n + 1 end end
        return n
    end
    if has(q, 'FROM rpg_events ORDER BY') then local out = {} for _, r in pairs(T.events) do out[#out + 1] = copy(r) end return out end
    if has(q, 'UPDATE rpg_events SET status') then if T.events[p[2]] then T.events[p[2]].status = p[1] end return 1 end
    if has(q, 'UPDATE rpg_events SET end_at') then if T.events[p[2]] then T.events[p[2]].end_at = p[1] end return 1 end
    if has(q, 'UPDATE rpg_events SET reminders_sent') then if T.events[p[2]] then T.events[p[2]].reminders_sent = p[1] end return 1 end
    -- claims / logs
    if has(q, 'INSERT INTO rpg_claims') then
        if T.claims[p[1]] then error('Duplicate entry for key PRIMARY') end
        T.claims[p[1]] = { citizenid = p[2], items = p[3] }
        return 1
    end
    if has(q, 'INSERT INTO rpg_audit_log') then T.audit[#T.audit + 1] = { actor = p[1], action = p[2], detail = p[3] } return #T.audit end
    if has(q, 'FROM rpg_audit_log') then return {} end
    if has(q, 'INSERT INTO rpg_run_history') then T.history[#T.history + 1] = { run_id = p[1], result = p[4], test = p[7] } return 1 end
    error('unmocked query: ' .. q)
end

local function wrap(fn)
    return setmetatable({ await = function(q, p) Wait(0) return fn(q, p) end }, {
        __call = function(_, q, p, cb) CreateThread(function() local r = fn(q, p) if cb then cb(r) end end) end,
    })
end
MySQL = {
    query = wrap(exec), scalar = wrap(exec), single = wrap(exec), insert = wrap(exec), update = wrap(exec),
    transaction = { await = function(queries)
        Wait(0)
        -- 疑似トランザクション: 失敗したら全てロールバック
        local snapshot = {}
        for k, v in pairs(T) do snapshot[k] = {} for kk, vv in pairs(v) do snapshot[k][kk] = copy(vv) end end
        for _, qq in ipairs(queries) do
            local ok = pcall(exec, qq.query, qq.values)
            if not ok then
                for k, v in pairs(snapshot) do T[k] = v end
                MOCK.db = T
                return false
            end
        end
        return true
    end },
}
