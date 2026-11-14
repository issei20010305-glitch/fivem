--[[ Qbox / ox_inventory ブリッジ ]]
Bridge = {}

function Bridge.GetPlayer(src)
    if not src then return nil end
    return exports.qbx_core:GetPlayer(src)
end

function Bridge.GetCitizenId(src)
    local p = Bridge.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

function Bridge.GetName(src)
    local p = Bridge.GetPlayer(src)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if ci and ci.firstname then return (('%s %s'):format(ci.lastname or '', ci.firstname or ''):gsub('^%s+', '')) end
    return GetPlayerName(src) or ('ID ' .. tostring(src))
end

function Bridge.GetSourceByCitizenId(cid)
    local p = exports.qbx_core:GetPlayerByCitizenId(cid)
    return p and p.PlayerData and p.PlayerData.source or nil
end

function Bridge.IsAdmin(src)
    if not src or src == 0 then return src == 0 end
    for _, ace in ipairs(Config.AdminAces) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end

function Bridge.Notify(src, msg, kind, duration)
    TriggerClientEvent('projectin_rpg:client:toast', src, { message = msg, type = kind or 'info', duration = duration or 5000 })
end

function Bridge.Log(actor, action, detail)
    MySQL.insert('INSERT INTO rpg_audit_log (actor, action, detail) VALUES (?, ?, ?)', {
        actor and tostring(actor) or nil, action, detail and json.encode(detail) or nil,
    })
    if Config.Debug then print(('[projectin_rpg] %s %s %s'):format(actor or '-', action, detail and json.encode(detail) or '')) end
end

function Bridge.IsPlayerRestricted(src)
    -- 手錠/死亡中などは入場不可 (Qbox標準のステートバッグ名。環境に合わせて追加してください)
    local st = Player(src).state
    if st.isDead or st.isHandcuffed or st.isCuffed or st.inLaststand then return true end
    local p = Bridge.GetPlayer(src)
    local md = p and p.PlayerData and p.PlayerData.metadata
    if md and (md.isdead or md.inlaststand or md.ishandcuffed) then return true end
    return false
end

---------------------------------------------------------------------------
-- ox_inventory
---------------------------------------------------------------------------
Inv = {}

function Inv.Items(inv)
    local items = exports.ox_inventory:GetInventoryItems(inv)
    return items or {}
end

function Inv.Add(inv, name, count, metadata, slot)
    local ok, resp = exports.ox_inventory:AddItem(inv, name, count, metadata, slot)
    return ok and true or false, resp
end

function Inv.Remove(inv, name, count, metadata, slot)
    local ok = exports.ox_inventory:RemoveItem(inv, name, count, metadata, slot)
    return ok and true or false
end

function Inv.RegisterStash(id, label, slots, weight)
    -- 存在しないグループを要求して、誰もクライアントから開けないようにする
    exports.ox_inventory:RegisterStash(id, label, slots, weight, false, { __projectin_rpg_locked = 0 })
end

function Inv.Disarm(src)
    TriggerClientEvent('ox_inventory:disarm', src, true)
end
