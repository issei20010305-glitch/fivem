--[[ ゲーム内エディター (管理者専用) ]]
Editor = {}
local MAX_JSON = 262144

local function guard(src)
    if not Bridge.IsAdmin(src) then return false end
    return true
end

local function actor(src) return Bridge.GetCitizenId(src) or ('src:' .. tostring(src)) end

function Editor.List(src)
    if not guard(src) then return nil end
    local rows = MySQL.query.await('SELECT id, name, type, status, version, has_unpublished, draft_data, updated_by, updated_at FROM rpg_definitions WHERE status <> ? ORDER BY updated_at DESC', { 'archived' }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local d = DB.Decode(r.draft_data, {})
        local _, err = RPG.Schema.Sanitize(d)
        out[#out + 1] = {
            id = r.id, name = r.name, type = r.type, status = r.status, version = r.version,
            hasUnpublished = r.has_unpublished == 1 or r.has_unpublished == true, updatedBy = r.updated_by,
            updatedAt = tostring(r.updated_at), summary = RPG.Schema.Summary(d), valid = err == nil, error = err,
        }
    end
    return out
end

function Editor.Get(src, id)
    if not guard(src) then return nil end
    local row = MySQL.single.await('SELECT * FROM rpg_definitions WHERE id = ?', { tonumber(id) })
    if not row then return nil end
    return { id = row.id, status = row.status, version = row.version, data = DB.Decode(row.draft_data, {}) }
end

local function encodeDraft(data)
    if type(data) ~= 'table' then return nil, 'データが不正です' end
    local ok, s = pcall(json.encode, data)
    if not ok or not s then return nil, 'データを保存できません' end
    if #s > MAX_JSON then return nil, 'データが大きすぎます' end
    return s
end

function Editor.Create(src, data)
    if not guard(src) then return false, '権限がありません' end
    data = type(data) == 'table' and data or {}
    data.name = type(data.name) == 'string' and data.name ~= '' and data.name:sub(1, Config.EditorLimits.maxNameLength) or '新しいダンジョン'
    data.type = data.type == 'raid' and 'raid' or 'dungeon'
    local s, err = encodeDraft(data)
    if not s then return false, err end
    local id = MySQL.insert.await('INSERT INTO rpg_definitions (name, type, status, draft_data, created_by, updated_by) VALUES (?, ?, ?, ?, ?, ?)',
        { data.name, data.type, 'draft', s, actor(src), actor(src) })
    Bridge.Log(actor(src), 'editor_create', { id = id })
    return id ~= nil, id
end

function Editor.SaveDraft(src, id, data)
    if not guard(src) then return false, '権限がありません' end
    id = tonumber(id)
    local s, err = encodeDraft(data)
    if not s then return false, err end
    local name = type(data.name) == 'string' and data.name:sub(1, Config.EditorLimits.maxNameLength) or '無題'
    local typ = data.type == 'raid' and 'raid' or 'dungeon'
    local affected = MySQL.update.await('UPDATE rpg_definitions SET draft_data = ?, name = ?, type = ?, has_unpublished = 1, updated_by = ? WHERE id = ?',
        { s, name, typ, actor(src), id })
    if (affected or 0) < 1 then return false, '定義が見つかりません' end
    local _, verr = RPG.Schema.Sanitize(data)
    return true, verr -- verr があれば「未完成」として警告表示
end

function Editor.Validate(src, data)
    if not guard(src) then return false, '権限がありません' end
    local clean, err = RPG.Schema.Sanitize(data)
    if not clean then return false, err end
    return true, RPG.Schema.Summary(clean)
end

function Editor.Duplicate(src, id)
    if not guard(src) then return false, '権限がありません' end
    local row = MySQL.single.await('SELECT * FROM rpg_definitions WHERE id = ?', { tonumber(id) })
    if not row then return false, '見つかりません' end
    local data = DB.Decode(row.draft_data, {})
    data.name = ((data.name or row.name) .. ' (コピー)'):sub(1, Config.EditorLimits.maxNameLength)
    return Editor.Create(src, data)
end

function Editor.Publish(src, id)
    if not guard(src) then return false, '権限がありません' end
    id = tonumber(id)
    local row = MySQL.single.await('SELECT * FROM rpg_definitions WHERE id = ?', { id })
    if not row then return false, '見つかりません' end
    local clean, err = RPG.Schema.Sanitize(DB.Decode(row.draft_data, {}))
    if not clean then return false, '公開できません: ' .. err end
    local s = json.encode(clean)
    MySQL.update.await("UPDATE rpg_definitions SET published_data = ?, status = 'published', version = version + 1, has_unpublished = 0, name = ?, type = ?, updated_by = ? WHERE id = ?",
        { s, clean.name, clean.type, actor(src), id })
    Events.RefreshDefinition(id, clean)
    Bridge.Log(actor(src), 'editor_publish', { id = id, version = (row.version or 0) + 1 })
    return true
end

function Editor.Archive(src, id)
    if not guard(src) then return false, '権限がありません' end
    id = tonumber(id)
    local live = MySQL.scalar.await("SELECT COUNT(*) FROM rpg_events WHERE definition_id = ? AND status IN ('scheduled','announced','active')", { id })
    if (live or 0) > 0 then return false, '予定/開催中のイベントがあるためアーカイブできません' end
    MySQL.update.await("UPDATE rpg_definitions SET status = 'archived', updated_by = ? WHERE id = ?", { actor(src), id })
    Bridge.Log(actor(src), 'editor_archive', { id = id })
    return true
end

function Editor.Test(src, id, role)
    if not guard(src) then return false, '権限がありません' end
    if Instances.GetRunOf(src) then return false, '既にインスタンス内にいます' end
    if not Config.Roles[role] then return false, 'テスト用ロールを選択してください' end
    local row = MySQL.single.await('SELECT * FROM rpg_definitions WHERE id = ?', { tonumber(id) })
    if not row then return false, '見つかりません' end
    local clean, err = RPG.Schema.Sanitize(DB.Decode(row.draft_data, {}))
    if not clean then return false, 'テストできません: ' .. err end
    Bridge.Log(actor(src), 'editor_test', { id = row.id, role = role })
    local ok, res = Instances.Start(clean, { src }, { defId = row.id, testMode = true, roleOverride = { [src] = role } })
    if not ok then return false, res end
    return true
end

---------------------------------------------------------------------------
-- テンプレート
---------------------------------------------------------------------------
function Editor.Templates(src, kind)
    if not guard(src) then return nil end
    local rows
    if kind then
        rows = MySQL.query.await('SELECT id, kind, name, data, created_by FROM rpg_templates WHERE kind = ? ORDER BY id', { kind })
    else
        rows = MySQL.query.await('SELECT id, kind, name, data, created_by FROM rpg_templates ORDER BY kind, id')
    end
    for _, r in ipairs(rows or {}) do r.data = DB.Decode(r.data, {}) end
    return rows or {}
end

function Editor.SaveTemplate(src, kind, name, data)
    if not guard(src) then return false, '権限がありません' end
    if kind ~= 'definition' and kind ~= 'enemy' then return false, '種類が不正です' end
    if type(name) ~= 'string' or name == '' then return false, 'テンプレート名を入力してください' end
    if kind == 'enemy' then
        data = RPG.Schema.SanitizeEnemy(data)
        if not data then return false, '敵データが不正です(モデル名必須)' end
    end
    local s, err = encodeDraft(data)
    if not s then return false, err end
    local id = MySQL.insert.await('INSERT INTO rpg_templates (kind, name, data, created_by) VALUES (?, ?, ?, ?)',
        { kind, name:sub(1, 64), s, actor(src) })
    return id ~= nil, id
end

function Editor.DeleteTemplate(src, id)
    if not guard(src) then return false, '権限がありません' end
    MySQL.update.await('DELETE FROM rpg_templates WHERE id = ?', { tonumber(id) })
    return true
end

function Editor.CreateFromTemplate(src, templateId)
    if not guard(src) then return false, '権限がありません' end
    local row = MySQL.single.await("SELECT * FROM rpg_templates WHERE id = ? AND kind = 'definition'", { tonumber(templateId) })
    if not row then return false, 'テンプレートが見つかりません' end
    local data = DB.Decode(row.data, {})
    data.name = ((data.name or row.name) .. ' (新規)'):sub(1, Config.EditorLimits.maxNameLength)
    return Editor.Create(src, data)
end
