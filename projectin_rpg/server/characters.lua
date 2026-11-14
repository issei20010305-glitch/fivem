--[[ キャラクター単位のRPGデータ (ロール / RPGインベントリ / 統計) ]]
Chars = {}
local cache = {}
local locks = {}

function Chars.WithLock(cid, fn)
    local waited = 0
    while locks[cid] do
        Wait(0)
        waited = waited + 1
        if waited > 3000 then return false, 'busy' end
    end
    locks[cid] = true
    local ok, a, b = pcall(fn)
    locks[cid] = nil
    if not ok then
        print(('[projectin_rpg] ^1エラー (%s): %s^0'):format(cid, tostring(a)))
        return false, 'internal'
    end
    return a, b
end

local function decodeItems(s)
    local list = DB.Decode(s, {})
    local items = {}
    for _, it in ipairs(list) do
        local slot = tonumber(it.slot)
        if slot and it.name and RPG.Items[it.name] and (tonumber(it.count) or 0) > 0 then
            items[math.floor(slot)] = { name = it.name, count = math.floor(it.count), meta = it.meta }
        end
    end
    return items
end

local function encodeItems(items)
    local list = {}
    for slot, it in pairs(items) do
        list[#list + 1] = { slot = slot, name = it.name, count = it.count, meta = it.meta }
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return json.encode(list)
end

function Chars.Load(cid)
    if cache[cid] then return cache[cid] end
    local row = MySQL.single.await('SELECT * FROM rpg_characters WHERE citizenid = ?', { cid })
    if not row then
        MySQL.insert.await('INSERT IGNORE INTO rpg_characters (citizenid, inventory, overflow, stats) VALUES (?, ?, ?, ?)',
            { cid, '[]', '[]', '{}' })
        row = { citizenid = cid, role = nil, inventory = '[]', overflow = '[]', stats = '{}' }
    end
    if cache[cid] then return cache[cid] end -- 並行ロード対策
    local c = {
        cid = cid,
        role = (row.role and Config.Roles[row.role]) and row.role or nil,
        items = decodeItems(row.inventory),
        overflow = DB.Decode(row.overflow, {}),
        stats = DB.Decode(row.stats, {}),
    }
    cache[cid] = c
    return c
end

function Chars.Get(cid) return cache[cid] end

function Chars.Unload(cid) cache[cid] = nil end

function Chars.SaveInventory(c)
    MySQL.update.await('UPDATE rpg_characters SET inventory = ?, overflow = ? WHERE citizenid = ?',
        { encodeItems(c.items), json.encode(c.overflow or {}), c.cid })
end

function Chars.SaveStats(c)
    MySQL.update('UPDATE rpg_characters SET stats = ? WHERE citizenid = ?', { json.encode(c.stats or {}), c.cid })
end

-- プレイヤー自身による初回のロール選択 (一度きり。DB側でも role IS NULL を条件に原子的に更新)
function Chars.ChooseRole(src, role)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false, 'キャラクター情報を取得できません' end
    if not Config.Roles[role] then return false, '不正なロールです' end
    return Chars.WithLock(cid, function()
        local c = Chars.Load(cid)
        if c.role then return false, 'ロールは既に決定済みです(変更は管理者のみ)' end
        local affected = MySQL.update.await('UPDATE rpg_characters SET role = ?, role_set_at = ? WHERE citizenid = ? AND role IS NULL',
            { role, os.time(), cid })
        if (affected or 0) < 1 then return false, 'ロールは既に決定済みです' end
        c.role = role
        Bridge.Log(cid, 'role_choose', { role = role })
        return true
    end)
end

-- 管理者によるロール変更/リセット
function Chars.AdminSetRole(adminSrc, cid, role)
    if not Bridge.IsAdmin(adminSrc) then return false, '権限がありません' end
    if role ~= nil and not Config.Roles[role] then return false, '不正なロールです' end
    if type(cid) ~= 'string' or #cid > 50 then return false, '不正なCitizenIDです' end
    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM rpg_characters WHERE citizenid = ?', { cid })
    if (exists or 0) == 0 then
        local pexists = MySQL.scalar.await('SELECT COUNT(*) FROM players WHERE citizenid = ?', { cid })
        if (pexists or 0) == 0 then return false, 'キャラクターが見つかりません' end
    end
    -- 入場中のキャラは変更不可 (効果の整合性のため)
    local src = Bridge.GetSourceByCitizenId(cid)
    if src and Instances and Instances.GetRunOf(src) then return false, 'ダンジョン/レイド参加中は変更できません' end
    return Chars.WithLock(cid, function()
        local c = Chars.Load(cid)
        MySQL.update.await('UPDATE rpg_characters SET role = ?, role_set_at = ? WHERE citizenid = ?', { role, role and os.time() or nil, cid })
        local old = c.role
        c.role = role
        Bridge.Log(Bridge.GetCitizenId(adminSrc) or adminSrc, 'role_admin_set', { target = cid, from = old, to = role })
        if src then
            TriggerClientEvent('projectin_rpg:client:profileChanged', src)
            Bridge.Notify(src, role and ('管理者によりロールが「%s」に変更されました'):format(Config.Roles[role].label)
                or '管理者によりロールがリセットされました。/rpg で再選択してください', 'info')
        end
        return true
    end)
end

function Chars.AddStat(cid, key, amount)
    local c = cache[cid]
    if not c then return end
    c.stats[key] = (tonumber(c.stats[key]) or 0) + (amount or 1)
end
