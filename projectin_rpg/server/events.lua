--[[
    期間限定イベント (日本時間でスケジュール & 告知)
    dungeon: start_at〜end_at の間、入口からパーティーが何度でも入場可能
    raid   : announce_at〜start_at の間に入口で参加登録 → start_at に一斉開始
]]
Events = {}
local U = RPG.Utils
local events = {}       -- id -> event (DB行 + def)
local raidLobby = {}    -- eventId -> { [src] = true }

local function now() return os.time() end

local function setStatus(ev, status)
    ev.status = status
    MySQL.update('UPDATE rpg_events SET status = ? WHERE id = ?', { status, ev.id })
end

local function saveReminders(ev)
    local list = {}
    for k in pairs(ev.reminders) do list[#list + 1] = tostring(k) end
    MySQL.update('UPDATE rpg_events SET reminders_sent = ? WHERE id = ?', { table.concat(list, ','), ev.id })
end

function Events.LoadDefinition(defId)
    local row = MySQL.single.await('SELECT published_data FROM rpg_definitions WHERE id = ? AND status = ?', { defId, 'published' })
    if not row or not row.published_data then return nil end
    return DB.Decode(row.published_data, nil)
end

local function publicList()
    local list = {}
    local t = now()
    for id, ev in pairs(events) do
        if (ev.status == 'announced' or ev.status == 'active') and ev.def then
            local count = 0
            for _ in pairs(raidLobby[id] or {}) do count = count + 1 end
            list[#list + 1] = {
                id = id, name = ev.name, type = ev.type, status = ev.status, location = ev.location_label,
                entry = ev.def.entry, description = ev.def.description, recommended = ev.def.recommended,
                minPlayers = ev.def.minPlayers, maxPlayers = ev.def.maxPlayers, timeLimit = ev.def.timeLimit,
                startIn = ev.start_at - t, endIn = ev.end_at - t,
                startLabel = U.formatJstRelativeDay(ev.start_at, t), endLabel = U.formatJstRelativeDay(ev.end_at, t),
                startJst = U.formatJst(ev.start_at), endJst = U.formatJst(ev.end_at),
                registered = count,
            }
        end
    end
    table.sort(list, function(a, b) return a.startIn < b.startIn end)
    return list
end
Events.PublicList = publicList

function Events.Broadcast(target)
    TriggerClientEvent('projectin_rpg:client:events', target or -1, publicList())
end

local function announce(ev, key, kind)
    local tmpl = (ev.announcement and ev.announcement ~= '' and key ~= 'raid_reminder' and key ~= 'dungeon_reminder' and key ~= 'raid_start') and ev.announcement
        or (ev.def and ev.def.announcements and ev.def.announcements[key]) or Config.DefaultAnnouncements[key]
    local text = U.formatAnnouncement(tmpl, ev, now())
    TriggerClientEvent('projectin_rpg:client:announce', -1, {
        title = ev.type == 'raid' and '大型ボスレイド' or 'ダンジョン発生', text = text, kind = kind or ev.type,
        location = ev.location_label, entry = ev.def and ev.def.entry, eventId = ev.id,
    })
end

function Events.Load()
    local rows = MySQL.query.await("SELECT * FROM rpg_events WHERE status IN ('scheduled', 'announced', 'active')") or {}
    local t = now()
    for _, row in ipairs(rows) do
        row.reminders = {}
        for k in tostring(row.reminders_sent or ''):gmatch('[^,]+') do row.reminders[k] = true end
        if row.end_at <= t then
            setStatus(row, 'ended')
        elseif row.type == 'raid' and row.status == 'active' then
            setStatus(row, 'ended') -- 再起動でレイドは継続不能
        elseif row.type == 'raid' and row.start_at <= t and row.status ~= 'active' then
            setStatus(row, 'ended')
        else
            row.def = Events.LoadDefinition(row.definition_id)
            if row.def then events[row.id] = row else setStatus(row, 'cancelled') end
        end
    end
end

---------------------------------------------------------------------------
-- 作成 / 管理 (管理者)
---------------------------------------------------------------------------
--- data: { definitionId, start (JST文字列), ['end'] (JST文字列, dungeon), announce (JST文字列 or nil=即時), location, announcement }
function Events.Create(src, data)
    if not Bridge.IsAdmin(src) then return false, '権限がありません' end
    if type(data) ~= 'table' then return false, '不正なデータ' end
    local defId = tonumber(data.definitionId)
    local def = defId and Events.LoadDefinition(defId)
    if not def then return false, '公開済みのダンジョン/レイドを選択してください' end
    local startAt = U.parseJst(data.start)
    if not startAt then return false, '開始日時の形式が不正です (例: 2026-11-14 21:00)' end
    local t = now()
    local endAt
    if def.type == 'dungeon' then
        endAt = U.parseJst(data['end'])
        if not endAt then return false, '終了日時の形式が不正です (例: 2026-11-14 24:00)' end
    else
        endAt = startAt + def.timeLimit + 600
    end
    if endAt <= startAt then return false, '終了は開始より後にしてください' end
    if endAt <= t then return false, '終了日時が過去です' end
    if endAt - startAt > 14 * 86400 then return false, '期間は最大14日です' end
    local announceAt = data.announce and data.announce ~= '' and U.parseJst(data.announce) or nil
    if data.announce and data.announce ~= '' and not announceAt then return false, '告知日時の形式が不正です' end
    if not announceAt then
        announceAt = def.type == 'raid' and math.max(t, startAt - 30 * 60) or startAt
    end
    if announceAt > startAt then return false, '告知は開始以前にしてください' end
    if def.type == 'raid' and startAt <= t + 60 then return false, 'レイドの開始は1分以上先にしてください' end
    local location = type(data.location) == 'string' and data.location:sub(1, 64) or ''
    if location == '' then location = def.locationLabel ~= '' and def.locationLabel or def.name end
    local announcement = type(data.announcement) == 'string' and data.announcement:gsub('[%c]', ''):sub(1, 200) or nil
    local cid = Bridge.GetCitizenId(src)
    local id = MySQL.insert.await([[INSERT INTO rpg_events (definition_id, name, type, location_label, announce_at, start_at, end_at, status, announcement, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'scheduled', ?, ?)]], { defId, def.name, def.type, location, announceAt, startAt, endAt, announcement, cid })
    if not id then return false, 'DB保存に失敗しました' end
    events[id] = {
        id = id, definition_id = defId, name = def.name, type = def.type, location_label = location,
        announce_at = announceAt, start_at = startAt, end_at = endAt, status = 'scheduled', reminders = {},
        announcement = announcement, def = def,
    }
    Bridge.Log(cid, 'event_create', { id = id, def = defId, start = U.formatJst(startAt), ['end'] = U.formatJst(endAt) })
    Events.Tick()
    return true, id
end

function Events.Cancel(src, id)
    if not Bridge.IsAdmin(src) then return false, '権限がありません' end
    local ev = events[tonumber(id)]
    if not ev then return false, 'イベントが見つかりません' end
    setStatus(ev, 'cancelled')
    events[ev.id] = nil
    raidLobby[ev.id] = nil
    TriggerClientEvent('projectin_rpg:client:announce', -1, { title = 'お知らせ', text = ('%sの%sは中止されました'):format(ev.location_label, ev.name), kind = 'info' })
    Events.Broadcast()
    Bridge.Log(Bridge.GetCitizenId(src), 'event_cancel', { id = ev.id })
    return true
end

function Events.EndNow(src, id)
    if not Bridge.IsAdmin(src) then return false, '権限がありません' end
    local ev = events[tonumber(id)]
    if not ev then return false, 'イベントが見つかりません' end
    ev.end_at = now()
    MySQL.update('UPDATE rpg_events SET end_at = ? WHERE id = ?', { ev.end_at, ev.id })
    Events.Tick()
    return true
end

function Events.AnnounceNow(src, id)
    if not Bridge.IsAdmin(src) then return false, '権限がありません' end
    local ev = events[tonumber(id)]
    if not ev or (ev.status ~= 'announced' and ev.status ~= 'active') then return false, '告知中/開催中のイベントのみ再告知できます' end
    announce(ev, ev.type == 'raid' and (ev.status == 'active' and 'raid_start' or 'raid_reminder') or 'dungeon_open')
    return true
end

function Events.AdminList()
    local rows = MySQL.query.await('SELECT * FROM rpg_events ORDER BY start_at DESC LIMIT 60') or {}
    local t = now()
    for _, r in ipairs(rows) do
        r.startJst = U.formatJst(r.start_at)
        r.endJst = U.formatJst(r.end_at)
        r.announceJst = U.formatJst(r.announce_at)
        r.live = events[r.id] ~= nil
        local count = 0
        for _ in pairs(raidLobby[r.id] or {}) do count = count + 1 end
        r.registered = count
        r.startIn = r.start_at - t
    end
    return rows
end

--- 告知プレビュー (保存しない)
function Events.Preview(data)
    data = type(data) == 'table' and data or {}
    local t = now()
    local startAt = U.parseJst(data.start) or (t + 1800)
    local endAt = U.parseJst(data['end']) or (startAt + 3600)
    local ev = { name = data.name or 'ダンジョン', location_label = (data.location ~= '' and data.location) or 'XXX番地', start_at = startAt, end_at = endAt }
    local out = {}
    local keys = data.type == 'raid' and { 'raid_announce', 'raid_reminder', 'raid_start' } or { 'dungeon_open', 'dungeon_reminder' }
    for _, k in ipairs(keys) do
        local tmpl = (k == 'raid_announce' or k == 'dungeon_open') and data.announcement and data.announcement ~= '' and data.announcement
            or (type(data.templates) == 'table' and data.templates[k]) or Config.DefaultAnnouncements[k]
        -- 告知タイミングでの表示を再現
        local at = t
        if k == 'raid_announce' then at = U.parseJst(data.announce) or math.max(t, startAt - 1800)
        elseif k == 'raid_reminder' then at = startAt - 300
        elseif k == 'raid_start' then at = startAt
        elseif k == 'dungeon_open' then at = U.parseJst(data.announce) or startAt
        elseif k == 'dungeon_reminder' then at = endAt - 3600 end
        out[#out + 1] = { key = k, at = U.formatJst(at), text = U.formatAnnouncement(tmpl, ev, at) }
    end
    return out
end

---------------------------------------------------------------------------
-- ダンジョン入場
---------------------------------------------------------------------------
local function eligible(src, ev)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false, 'キャラクター未ロード' end
    local c = Chars.Load(cid)
    if not c.role then return false, 'ロール未選択 (/rpg で選択)' end
    if Instances.GetRunOf(src) then return false, '既に参加中' end
    if GetPlayerRoutingBucket(src) ~= 0 then return false, '別の空間にいます' end
    if Bridge.IsPlayerRestricted(src) then return false, '現在入場できない状態です' end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false, '車両から降りてください' end
    local e = ev.def.entry
    if #(GetEntityCoords(ped) - vector3(e.x, e.y, e.z)) > Config.Party.entryRange then return false, '入口から離れすぎています' end
    return true
end

function Events.EntryCheck(src, eventId)
    local ev = events[tonumber(eventId)]
    if not ev or not ev.def then return nil, 'イベントが見つかりません' end
    local party = Parties.Get(src)
    local members = party and Parties.Members(party) or { src }
    local list = {}
    for _, s in ipairs(members) do
        local ok, why = eligible(s, ev)
        local cid = Bridge.GetCitizenId(s)
        local c = cid and Chars.Get(cid)
        list[#list + 1] = { id = s, name = Bridge.GetName(s), ok = ok, reason = why, role = c and c.role,
            roleLabel = c and c.role and Config.Roles[c.role].label or '未選択' }
    end
    local reg = raidLobby[ev.id] or {}
    return {
        event = { id = ev.id, name = ev.name, type = ev.type, status = ev.status, location = ev.location_label,
            description = ev.def.description, recommended = ev.def.recommended, minPlayers = ev.def.minPlayers, maxPlayers = ev.def.maxPlayers,
            timeLimit = ev.def.timeLimit, startIn = ev.start_at - now(), endLabel = U.formatJstRelativeDay(ev.end_at), waves = #ev.def.waves,
            hasBoss = ev.def.boss ~= nil, registered = U.tcount(reg) },
        members = list, isLeader = not party or party.leader == src, registered = reg[src] == true,
    }
end

function Events.EnterDungeon(src, eventId)
    local ev = events[tonumber(eventId)]
    if not ev or not ev.def then return false, 'イベントが見つかりません' end
    if ev.type ~= 'dungeon' then return false, 'これはレイドです。参加登録してください' end
    local t = now()
    if ev.status ~= 'active' or t < ev.start_at then return false, 'まだ開始されていません' end
    if t >= ev.end_at then return false, 'イベントは終了しました' end
    local party = Parties.Get(src)
    if party and party.leader ~= src then return false, 'パーティーリーダーのみ入場を開始できます' end
    local members = party and Parties.Members(party) or { src }
    if #members < ev.def.minPlayers then return false, ('%d人以上で入場してください'):format(ev.def.minPlayers) end
    if #members > ev.def.maxPlayers then return false, ('最大%d人までです'):format(ev.def.maxPlayers) end
    for _, s in ipairs(members) do
        local ok, why = eligible(s, ev)
        if not ok then return false, ('%s: %s'):format(Bridge.GetName(s), why) end
    end
    return Instances.Start(ev.def, members, { defId = ev.definition_id, eventId = ev.id })
end

---------------------------------------------------------------------------
-- レイド参加登録
---------------------------------------------------------------------------
function Events.RaidRegister(src, eventId, unregister)
    local ev = events[tonumber(eventId)]
    if not ev or ev.type ~= 'raid' then return false, 'レイドが見つかりません' end
    raidLobby[ev.id] = raidLobby[ev.id] or {}
    if unregister then
        raidLobby[ev.id][src] = nil
        Events.Broadcast()
        return true, '参加登録を取り消しました'
    end
    if ev.status ~= 'announced' or now() >= ev.start_at then return false, '登録受付期間外です' end
    local cid = Bridge.GetCitizenId(src)
    local c = cid and Chars.Load(cid)
    if not c or not c.role then return false, 'ロール未選択です (/rpg)' end
    if U.tcount(raidLobby[ev.id]) >= ev.def.maxPlayers then return false, '定員に達しました' end
    local e = ev.def.entry
    if #(GetEntityCoords(GetPlayerPed(src)) - vector3(e.x, e.y, e.z)) > Config.Events.raidLobbyRange then return false, '集合地点から離れすぎています' end
    raidLobby[ev.id][src] = true
    Events.Broadcast()
    return true, ('参加登録しました。開始まで%s、集合地点付近で待機してください'):format(U.formatDuration(ev.start_at - now()))
end

local function startRaid(ev)
    local players = {}
    local e = ev.def.entry
    for src in pairs(raidLobby[ev.id] or {}) do
        if GetPlayerName(src) and not Instances.GetRunOf(src) and GetPlayerRoutingBucket(src) == 0 then
            local ped = GetPlayerPed(src)
            if ped ~= 0 and #(GetEntityCoords(ped) - vector3(e.x, e.y, e.z)) <= Config.Events.raidLobbyRange + 20.0 and not Bridge.IsPlayerRestricted(src) then
                players[#players + 1] = src
            else
                Bridge.Notify(src, '集合地点にいなかったためレイドに参加できませんでした', 'error')
            end
        end
        if #players >= ev.def.maxPlayers then break end
    end
    raidLobby[ev.id] = nil
    if #players < ev.def.minPlayers then
        setStatus(ev, 'ended')
        events[ev.id] = nil
        TriggerClientEvent('projectin_rpg:client:announce', -1, { title = '大型ボスレイド', text = ('%sのレイドは参加者不足のため中止されました'):format(ev.location_label), kind = 'info' })
        return
    end
    local ok, res = Instances.Start(ev.def, players, { defId = ev.definition_id, eventId = ev.id })
    if ok then
        ev.runId = res.id
        setStatus(ev, 'active')
        announce(ev, 'raid_start', 'raid')
    else
        setStatus(ev, 'ended')
        events[ev.id] = nil
        for _, s in ipairs(players) do Bridge.Notify(s, 'レイドを開始できませんでした: ' .. tostring(res), 'error') end
    end
end

---------------------------------------------------------------------------
-- スケジューラー
---------------------------------------------------------------------------
local ticking = false
function Events.Tick()
    if ticking then return end
    ticking = true
    local ok, err = pcall(Events._Tick)
    ticking = false
    if not ok then print('[projectin_rpg] ^1Events.Tick error: ' .. tostring(err) .. '^0') end
end

function Events._Tick()
    local t = now()
    local changed = false
    local ids = {}
    for id in pairs(events) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
      local ev = events[id]
      if ev then
        if ev.status == 'scheduled' and t >= ev.announce_at then
            if ev.type == 'dungeon' then
                if t >= ev.start_at then
                    setStatus(ev, 'active')
                    announce(ev, 'dungeon_open')
                else
                    setStatus(ev, 'announced')
                    announce(ev, 'dungeon_open')
                end
            else
                setStatus(ev, 'announced')
                announce(ev, 'raid_announce')
            end
            changed = true
        elseif ev.status == 'announced' and t >= ev.start_at then
            if ev.type == 'dungeon' then
                setStatus(ev, 'active')
            else
                startRaid(ev)
            end
            changed = true
        end

        -- リマインダー
        if ev.status == 'announced' and ev.type == 'raid' then
            for _, min in ipairs(Config.Events.raidReminderMinutes) do
                local key = 'r' .. min
                local left = ev.start_at - t
                if not ev.reminders[key] and left <= min * 60 and left > (min * 60 - 60) and t > ev.announce_at + 30 then
                    ev.reminders[key] = true
                    saveReminders(ev)
                    announce(ev, 'raid_reminder')
                end
            end
        elseif ev.status == 'active' and ev.type == 'dungeon' then
            for _, min in ipairs(Config.Events.dungeonReminderMinutes) do
                local key = 'e' .. min
                local left = ev.end_at - t
                if not ev.reminders[key] and left <= min * 60 and left > (min * 60 - 60) then
                    ev.reminders[key] = true
                    saveReminders(ev)
                    announce(ev, 'dungeon_reminder')
                end
            end
        end

        -- 終了
        if events[id] and t >= ev.end_at and ev.status ~= 'ended' then
            if ev.type == 'raid' and ev.runId and Instances.GetRun(ev.runId) then
                -- レイド実行中はインスタンス側の時間制限で終了する
            else
                setStatus(ev, 'ended')
                events[id] = nil
                raidLobby[id] = nil
                if ev.type == 'dungeon' then
                    TriggerClientEvent('projectin_rpg:client:announce', -1, { title = 'ダンジョン消滅', text = ('%sのダンジョンは消滅しました'):format(ev.location_label), kind = 'info' })
                end
                changed = true
            end
        end
        if events[id] and ev.type == 'raid' and ev.status == 'active' and ev.runId and not Instances.GetRun(ev.runId) then
            setStatus(ev, 'ended')
            events[id] = nil
            changed = true
        end
      end
    end
    if changed then Events.Broadcast() end
end

CreateThread(function()
    while not DB.Ready do Wait(500) end
    Events.Load()
    Events.Broadcast()
    local n = 0
    while true do
        Events.Tick()
        n = n + 1
        if n % 4 == 0 then Events.Broadcast() end -- 残り時間表示の更新
        Wait(Config.Events.tickSeconds * 1000)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, lobby in pairs(raidLobby) do lobby[src] = nil end
end)

-- 公開版が更新されたら、未開始/開催中(ダンジョン)のイベントへ反映
-- (実行中のインスタンスは開始時のコピーを使い続けます)
function Events.RefreshDefinition(defId, def)
    for _, ev in pairs(events) do
        if ev.definition_id == defId and not (ev.type == 'raid' and ev.status == 'active') then
            ev.def = def
        end
    end
    Events.Broadcast()
end
