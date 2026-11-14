--[[
    通常インベントリの預かり/復元
    入場時: ox_inventory の所持品を鍵付きスタッシュ rpghold_<citizenid> へ退避し、貸与装備(rpgLoaner)を付与
    退出時: 貸与装備を回収し、スタッシュから全て戻す
    - DBの rpg_holdings 行は「退避が始まる前」に作成するため、途中でクラッシュしても次回ログイン時に復元されます
    - 復元はスタッシュの中身そのものを正とするため何度実行しても安全(冪等)です
]]
Holding = {}
local H = Config.Holding
local keep = {}
for _, n in ipairs(H.keepItems) do keep[n] = true end

local function stashId(cid) return H.stashPrefix .. cid end

local function isLoaner(item)
    return type(item) == 'table' and type(item.metadata) == 'table' and item.metadata[H.loanerMetaKey] ~= nil
end

local function ensureStash(cid)
    Inv.RegisterStash(stashId(cid), 'RPG預かり品', H.stashSlots, H.stashWeight)
end

local function moveAll(fromInv, toInv, filter)
    local moved, failed = {}, {}
    for _, item in pairs(Inv.Items(fromInv)) do
        if item and item.name and item.count and item.count > 0 and (not filter or filter(item)) then
            local meta = item.metadata and next(item.metadata) and item.metadata or nil
            local ok = Inv.Add(toInv, item.name, item.count, meta)
            if ok then
                if Inv.Remove(fromInv, item.name, item.count, meta, item.slot) then
                    moved[#moved + 1] = { name = item.name, count = item.count, metadata = meta }
                else
                    Inv.Remove(toInv, item.name, item.count, meta) -- ロールバック
                    failed[#failed + 1] = item.name
                end
            else
                failed[#failed + 1] = item.name
            end
        end
    end
    return moved, failed
end

function Holding.RemoveLoaners(src)
    for _, item in pairs(Inv.Items(src)) do
        if isLoaner(item) then Inv.Remove(src, item.name, item.count, nil, item.slot) end
    end
end

function Holding.Has(cid)
    return (MySQL.scalar.await('SELECT COUNT(*) FROM rpg_holdings WHERE citizenid = ?', { cid }) or 0) > 0
end

--- 入場時の退避
function Holding.Hold(src, runId, returnPos, role)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false, 'キャラクター情報なし' end
    if Holding.Has(cid) then
        Holding.Restore(src)
        if Holding.Has(cid) then return false, '前回の預かり品の返却が完了していません。管理者に連絡してください' end
    end
    local ped = GetPlayerPed(src)
    local health = GetEntityHealth(ped)
    local armour = GetPedArmour(ped)
    Inv.Disarm(src)

    local snapshot = {}
    for _, item in pairs(Inv.Items(src)) do
        if item and item.name then snapshot[#snapshot + 1] = { name = item.name, count = item.count, slot = item.slot } end
    end

    MySQL.insert.await('INSERT INTO rpg_holdings (citizenid, run_id, return_pos, health, armour, snapshot) VALUES (?, ?, ?, ?, ?, ?)', {
        cid, runId, json.encode(returnPos), health > 0 and health or 200, armour, json.encode(snapshot),
    })

    if H.enabled then
        ensureStash(cid)
        local _, failed = moveAll(src, stashId(cid), function(item) return not keep[item.name] and not isLoaner(item) end)
        if #failed > 0 then
            -- 失敗時は全て元に戻して入場中止
            moveAll(stashId(cid), src)
            MySQL.query.await('DELETE FROM rpg_holdings WHERE citizenid = ?', { cid })
            Bridge.Log(cid, 'hold_failed', { failed = failed })
            return false, '所持品の預け入れに失敗したため入場を中止しました'
        end
    end

    -- 貸与装備
    local roleDef = Config.Roles[role]
    for _, l in ipairs(roleDef and roleDef.loadout or {}) do
        local meta = { [H.loanerMetaKey] = runId }
        if l.item:sub(1, 7) == 'WEAPON_' then meta.serial = 'RPG-LOANER' meta.registered = false end
        Inv.Add(src, l.item, l.count, meta)
    end
    Bridge.Log(cid, 'hold', { run = runId, items = #snapshot })
    return true, { health = health, armour = armour }
end

--- 復元 (冪等)
--- @param sync boolean trueならDB待機なし(リソース停止時用)
function Holding.Restore(src, sync)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return nil end
    local row
    if not sync then
        row = MySQL.single.await('SELECT * FROM rpg_holdings WHERE citizenid = ?', { cid })
        if not row then
            Holding.RemoveLoaners(src) -- 念のため
            return nil
        end
    end
    Inv.Disarm(src)
    Holding.RemoveLoaners(src)
    local failed = {}
    if H.enabled then
        ensureStash(cid)
        local _moved
        _moved, failed = moveAll(stashId(cid), src)
    end
    if #failed == 0 then
        if sync then
            MySQL.query('DELETE FROM rpg_holdings WHERE citizenid = ?', { cid })
        else
            MySQL.query.await('DELETE FROM rpg_holdings WHERE citizenid = ?', { cid })
        end
        Bridge.Log(cid, 'restore', { ok = true })
    else
        Bridge.Notify(src, '一部の所持品を返却できませんでした。所持重量を減らして再ログインするか管理者に連絡してください。', 'error', 12000)
        Bridge.Log(cid, 'restore_partial', { failed = failed })
    end
    if row then
        row.return_pos = DB.Decode(row.return_pos, nil)
    end
    return row
end

---------------------------------------------------------------------------
-- ox_inventory フック: 入場中の持ち出し/持ち込み、貸与品の流出を防止
---------------------------------------------------------------------------
local hookIds = {}

local function inRun(src)
    return type(src) == 'number' and Instances.GetRunOf(src) ~= nil
end

CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do Wait(500) end
    hookIds[#hookIds + 1] = exports.ox_inventory:registerHook('swapItems', function(payload)
        local fromType, toType = payload.fromType, payload.toType
        -- 貸与品はプレイヤー自身のインベントリ外へ移動不可 (どこにいても)
        local item = payload.fromSlot
        if type(item) == 'table' and isLoaner(item) and (toType ~= 'player' or payload.toInventory ~= payload.fromInventory) then
            return false
        end
        -- 入場中は自分のインベントリ内の並べ替え以外を全て禁止
        if inRun(payload.source) then
            if not (fromType == 'player' and toType == 'player' and payload.fromInventory == payload.toInventory) then
                return false
            end
        end
        -- 退避スタッシュへの直接アクセス禁止
        local function isHold(inv) return type(inv) == 'string' and inv:sub(1, #H.stashPrefix) == H.stashPrefix end
        if isHold(payload.fromInventory) or isHold(payload.toInventory) then return false end
        return true
    end, {})

    hookIds[#hookIds + 1] = exports.ox_inventory:registerHook('openInventory', function(payload)
        if inRun(payload.source) and payload.inventoryType ~= 'player' then return false end
        local id = payload.inventoryId
        if type(id) == 'string' and id:sub(1, #H.stashPrefix) == H.stashPrefix then return false end
        return true
    end, {})

    hookIds[#hookIds + 1] = exports.ox_inventory:registerHook('buyItem', function(payload)
        if inRun(payload.source) then return false end
        return true
    end, {})

    hookIds[#hookIds + 1] = exports.ox_inventory:registerHook('craftItem', function(payload)
        if inRun(payload.source) then return false end
        return true
    end, {})

    hookIds[#hookIds + 1] = exports.ox_inventory:registerHook('usingItem', function(payload)
        -- 入場中は貸与品以外のアイテム使用を禁止 (keepItems の携帯電話等は許可)
        if inRun(payload.source) then
            local it = payload.item
            if isLoaner(it) then return true end
            if it and keep[it.name] then return true end
            return false
        end
        return true
    end, {})
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if GetResourceState('ox_inventory') == 'started' then
        for _, id in ipairs(hookIds) do pcall(function() exports.ox_inventory:removeHooks(id) end) end
    end
end)
