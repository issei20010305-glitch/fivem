--[[ 管理画面のバックエンド ]]
Admin = {}

function Admin.Players(src)
    if not Bridge.IsAdmin(src) then return nil end
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        local cid = Bridge.GetCitizenId(s)
        if cid then
            local c = Chars.Load(cid)
            local run = Instances.GetRunOf(s)
            out[#out + 1] = { id = s, cid = cid, name = Bridge.GetName(s), role = c.role,
                roleLabel = c.role and Config.Roles[c.role].label or '未選択', inRun = run and run.name or nil }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Admin.LookupCid(src, cid)
    if not Bridge.IsAdmin(src) then return nil end
    if type(cid) ~= 'string' or #cid > 50 then return nil end
    local row = MySQL.single.await('SELECT citizenid, role, role_set_at FROM rpg_characters WHERE citizenid = ?', { cid })
    local p = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { cid })
    if not row and not p then return nil end
    local name = cid
    if p and p.charinfo then
        local ci = DB.Decode(p.charinfo, {})
        if ci.firstname then name = ('%s %s'):format(ci.lastname or '', ci.firstname) end
    end
    local role = row and row.role
    return { cid = cid, name = name, role = role, roleLabel = role and Config.Roles[role] and Config.Roles[role].label or '未選択' }
end

function Admin.Runs(src)
    if not Bridge.IsAdmin(src) then return nil end
    local out = {}
    for id, run in pairs(Instances.All()) do
        local members = {}
        for s, m in pairs(run.members) do
            if not m.left then members[#members + 1] = ('%s(%s)'):format(m.name, Config.Roles[m.role].label) end
        end
        local alive = 0
        for _, e in pairs(run.enemies) do if e.alive then alive = alive + 1 end end
        out[#out + 1] = {
            id = id, name = run.name, type = run.type, state = run.state, test = run.testMode, bucket = run.bucket,
            wave = run.wave, waves = #run.def.waves, members = members, enemies = alive, timeLeft = math.max(0, run.endsAt - os.time()),
        }
    end
    return out
end

function Admin.Logs(src)
    if not Bridge.IsAdmin(src) then return nil end
    local rows = MySQL.query.await('SELECT id, actor, action, detail, created_at FROM rpg_audit_log ORDER BY id DESC LIMIT 100') or {}
    for _, r in ipairs(rows) do r.created_at = tostring(r.created_at) end
    return rows
end
