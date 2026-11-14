--[[ コールバック / コマンド / プレイヤーライフサイクル ]]
local U = RPG.Utils

---------------------------------------------------------------------------
-- コールバック登録 (簡易レート制限付き)
---------------------------------------------------------------------------
local lastCall = {}
local function register(name, fn, minIntervalMs)
    lib.callback.register('projectin_rpg:' .. name, function(src, ...)
        if not DB.Ready then return false, '準備中です' end
        local key = src .. name
        local t = GetGameTimer()
        if minIntervalMs and lastCall[key] and t - lastCall[key] < minIntervalMs then return false, '操作が早すぎます' end
        lastCall[key] = t
        return fn(src, ...)
    end)
end

local function roleList()
    local out = {}
    for _, k in ipairs(Config.RoleOrder) do
        local r = Config.Roles[k]
        out[#out + 1] = { id = k, label = r.label, description = r.description, color = r.color, icon = r.icon,
            hpMult = r.hpMult, damageMult = r.damageMult, inventoryMult = r.inventoryMult, canAttack = r.canAttack }
    end
    return out
end

register('getProfile', function(src)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return nil end
    local c = Chars.Load(cid)
    local run = Instances.GetRunOf(src)
    return {
        cid = cid, name = Bridge.GetName(src), role = c.role, roles = roleList(), isAdmin = Bridge.IsAdmin(src),
        stats = c.stats, inRun = run and { name = run.name, type = run.type, state = run.state, test = run.testMode } or nil,
        events = Events.PublicList(), party = Parties.Payload(src),
        mage = { maxMp = Config.Mage.maxMp, skills = Config.Mage.skills },
        nowJst = U.formatJst(os.time()),
    }
end)

register('chooseRole', function(src, role) return Chars.ChooseRole(src, role) end, 1000)
register('getInventory', function(src) return RpgInv.Payload(src) end, 200)
register('invMove', function(src, from, to) return RpgInv.Move(src, from, to) end, 100)
register('invDiscard', function(src, slot, count) return RpgInv.Discard(src, slot, count) end, 300)
register('invUse', function(src, slot) return RpgInv.Use(src, slot) end, 300)
register('invClaimOverflow', function(src) return RpgInv.ClaimOverflow(src) end, 1000)

register('party', function(src, action, arg)
    if action == 'get' then return true, Parties.Payload(src)
    elseif action == 'create' then Parties.Create(src) return true
    elseif action == 'invite' then return Parties.Invite(src, arg)
    elseif action == 'accept' then return Parties.Accept(src, arg)
    elseif action == 'decline' then return Parties.Decline(src, arg)
    elseif action == 'leave' then return Parties.Leave(src)
    elseif action == 'kick' then return Parties.Kick(src, arg)
    elseif action == 'promote' then return Parties.Promote(src, arg)
    elseif action == 'nearby' then return true, Parties.Nearby(src)
    end
    return false, '不明な操作'
end, 150)

register('entryCheck', function(src, eventId) return Events.EntryCheck(src, eventId) end, 300)
register('enterDungeon', function(src, eventId)
    local ok, res = Events.EnterDungeon(src, eventId)
    if ok then return true end
    return false, res
end, 2000)
register('raidRegister', function(src, eventId, unregister) return Events.RaidRegister(src, eventId, unregister) end, 1000)
register('leaveRun', function(src) return Instances.Leave(src, 'leave') end, 2000)
register('pickup', function(src, dropId) return Instances.PickupDrop(src, dropId) end, 150)
register('interactStart', function(src, id) return Instances.InteractStart(src, id) end, 300)
register('interactFinish', function(src, id) return Instances.InteractFinish(src, id) end, 300)
register('skill', function(src, id, target) return Combat.UseSkill(src, id, target) end, 250)
register('getEvents', function(src) return Events.PublicList() end, 500)

---------------------------------------------------------------------------
-- 管理者
---------------------------------------------------------------------------
register('admin', function(src, action, p)
    if not Bridge.IsAdmin(src) then
        Bridge.Log(Bridge.GetCitizenId(src) or src, 'admin_denied', { action = action })
        return false, '権限がありません'
    end
    p = type(p) == 'table' and p or {}
    if action == 'players' then return true, Admin.Players(src)
    elseif action == 'lookup' then return true, Admin.LookupCid(src, p.cid)
    elseif action == 'setRole' then return Chars.AdminSetRole(src, p.cid, p.role ~= '' and p.role or nil)
    elseif action == 'runs' then return true, Admin.Runs(src)
    elseif action == 'forceEnd' then return Instances.ForceEnd(p.runId, src)
    elseif action == 'logs' then return true, Admin.Logs(src)
    elseif action == 'events' then return true, Events.AdminList()
    elseif action == 'eventCreate' then return Events.Create(src, p)
    elseif action == 'eventCancel' then return Events.Cancel(src, p.id)
    elseif action == 'eventEnd' then return Events.EndNow(src, p.id)
    elseif action == 'eventAnnounce' then return Events.AnnounceNow(src, p.id)
    elseif action == 'preview' then return true, Events.Preview(p)
    elseif action == 'defs' then return true, Editor.List(src)
    elseif action == 'defGet' then return true, Editor.Get(src, p.id)
    elseif action == 'defCreate' then return Editor.Create(src, p.data)
    elseif action == 'defSave' then return Editor.SaveDraft(src, p.id, p.data)
    elseif action == 'defValidate' then return Editor.Validate(src, p.data)
    elseif action == 'defDuplicate' then return Editor.Duplicate(src, p.id)
    elseif action == 'defPublish' then return Editor.Publish(src, p.id)
    elseif action == 'defArchive' then return Editor.Archive(src, p.id)
    elseif action == 'defTest' then return Editor.Test(src, p.id, p.role)
    elseif action == 'templates' then return true, Editor.Templates(src, p.kind)
    elseif action == 'templateSave' then return Editor.SaveTemplate(src, p.kind, p.name, p.data)
    elseif action == 'templateDelete' then return Editor.DeleteTemplate(src, p.id)
    elseif action == 'templateUse' then return Editor.CreateFromTemplate(src, p.id)
    elseif action == 'items' then
        local list = {}
        for k, v in pairs(RPG.Items) do list[#list + 1] = { id = k, label = v.label, icon = v.icon, rarity = v.rarity } end
        table.sort(list, function(a, b) return a.id < b.id end)
        return true, list
    elseif action == 'nowJst' then return true, U.formatJst(os.time())
    end
    return false, '不明な操作'
end, 100)

---------------------------------------------------------------------------
-- プレイヤーライフサイクル
---------------------------------------------------------------------------
local function inOurBucket(src)
    local b = GetPlayerRoutingBucket(src)
    return b >= Config.Instance.bucketStart and b <= Config.Instance.bucketMax
end

local restoring = {}
local function onLoaded(src)
    if restoring[src] then return end
    restoring[src] = true
    CreateThread(function()
        while not DB.Ready do Wait(500) end
        local cid = Bridge.GetCitizenId(src)
        if not cid then restoring[src] = nil return end
        Chars.Load(cid)
        if not Instances.GetRunOf(src) and Holding.Has(cid) then
            -- ox_inventory のプレイヤーインベントリ読み込みを待つ
            local waited = 0
            while waited < 15000 and not exports.ox_inventory:GetInventory(src, false) do
                Wait(250)
                waited = waited + 250
            end
            Wait(1000)
            local row = Holding.Restore(src)
            if inOurBucket(src) then SetPlayerRoutingBucket(src, 0) end
            Player(src).state:set('rpgRun', nil, true)
            if row then
                TriggerClientEvent('projectin_rpg:client:exitRun', src, {
                    pos = row.return_pos, health = row.health, armour = row.armour, reason = 'recover',
                })
                Bridge.Notify(src, '前回中断したダンジョンから帰還し、預かり品を返却しました', 'info', 8000)
            end
        elseif not Instances.GetRunOf(src) and inOurBucket(src) then
            SetPlayerRoutingBucket(src, 0)
        end
        TriggerClientEvent('projectin_rpg:client:events', src, Events.PublicList())
        restoring[src] = nil
    end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if src then onLoaded(src) end
end)

local readyAt = {}
RegisterNetEvent('projectin_rpg:server:clientReady', function()
    local src = source
    local t = os.time()
    if readyAt[src] and t - readyAt[src] < 10 then return end
    readyAt[src] = t
    if Bridge.GetCitizenId(src) then onLoaded(src) end
end)

local function onLogout(src)
    local cid = Bridge.GetCitizenId(src)
    if Instances.GetRunOf(src) then
        -- キャラクター切替: 所持品の復元は次回そのキャラでログインした時に行う
        Instances.Leave(src, 'drop')
        SetPlayerRoutingBucket(src, 0)
        Player(src).state:set('rpgRun', nil, true)
        TriggerClientEvent('projectin_rpg:client:forceCleanupNet', src)
    end
    Parties.Leave(src, true)
    if cid then Chars.Unload(cid) end
end

AddEventHandler('qbx_core:server:playerLoggedOut', function(src) onLogout(src) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) onLogout(src) end)

AddEventHandler('playerDropped', function()
    local src = source
    local cid = Bridge.GetCitizenId(src)
    if Instances.GetRunOf(src) then Instances.Leave(src, 'drop') end
    if cid then SetTimeout(5000, function() if not Bridge.GetSourceByCitizenId(cid) then Chars.Unload(cid) end end) end
    readyAt[src] = nil
    restoring[src] = nil
    for k in pairs(lastCall) do if k:sub(1, #tostring(src)) == tostring(src) then lastCall[k] = nil end end
end)

---------------------------------------------------------------------------
-- 起動
---------------------------------------------------------------------------
CreateThread(function()
    DB.Init()
    print('[projectin_rpg] ^2起動しました^0 (日本時間 ' .. U.formatJst(os.time()) .. ')')
    -- リソース再起動時: オンラインのプレイヤーの預かり品を復元
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        if Bridge.GetCitizenId(s) then onLoaded(s) end
    end
end)

---------------------------------------------------------------------------
-- コマンド
---------------------------------------------------------------------------
RegisterCommand('rpgadmin', function(src)
    if src == 0 then return print('ゲーム内で実行してください') end
    if not Bridge.IsAdmin(src) then return Bridge.Notify(src, '権限がありません', 'error') end
    TriggerClientEvent('projectin_rpg:client:openAdmin', src)
end, false)

-- コンソール用: rpgrole <citizenid> <tank|attacker|porter|mage|reset>
RegisterCommand('rpgrole', function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local cid, role = args[1], args[2]
    if not cid or not role then return print('使い方: rpgrole <citizenid> <tank|attacker|porter|mage|reset>') end
    local function run()
        -- Bridge.IsAdmin(0) はコンソールとして true を返す
        local ok, err = Chars.AdminSetRole(src, cid, role ~= 'reset' and role or nil)
        if src == 0 then
            print(ok and '変更しました' or ('失敗: ' .. tostring(err)))
        else
            Bridge.Notify(src, ok and '変更しました' or ('失敗: ' .. tostring(err)), ok and 'success' or 'error')
        end
    end
    CreateThread(run)
end, true)
