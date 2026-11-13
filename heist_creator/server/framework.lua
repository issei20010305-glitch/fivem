-- Qbox / ox_inventory bridge. Every framework specific call lives in this file.
Framework = {}

local policeCache = { count = 0, sources = {}, at = -1 }

---@param src number
function Framework.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

---@param src number
---@return string? citizenid
function Framework.GetIdentifier(src)
    local player = Framework.GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

---@param src number
---@return string
function Framework.GetName(src)
    local player = Framework.GetPlayer(src)
    if player and player.PlayerData.charinfo then
        local info = player.PlayerData.charinfo
        return ('%s %s'):format(info.firstname or '', info.lastname or '')
    end
    return GetPlayerName(src) or ('ID %s'):format(src)
end

---@param src number
function Framework.IsAdmin(src)
    return IsPlayerAceAllowed(tostring(src), ('command.%s'):format(Config.Commands.create))
end

local function refreshPolice()
    local now = os.time()
    if policeCache.at >= 0 and now - policeCache.at < Config.Police.cacheSeconds then return end

    local count, sources = 0, {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local player = src and Framework.GetPlayer(src)
        local job = player and player.PlayerData.job
        if job and Utils.Contains(Config.Police.jobs, job.name)
            and (not Config.Police.requireOnDuty or job.onduty) then
            count = count + 1
            sources[count] = src
        end
    end
    policeCache.count, policeCache.sources, policeCache.at = count, sources, now
end

---@return number
function Framework.GetPoliceCount()
    refreshPolice()
    return policeCache.count
end

---@return number[]
function Framework.GetPoliceSources()
    refreshPolice()
    return policeCache.sources
end

---------------------------------------------------------------------------
-- Inventory (ox_inventory)
---------------------------------------------------------------------------
local itemList

---@param name string
function Framework.ItemExists(name)
    return type(name) == 'string' and name ~= '' and exports.ox_inventory:Items(name) ~= nil
end

---@param name string
function Framework.ItemLabel(name)
    local item = exports.ox_inventory:Items(name)
    return item and item.label or name
end

---Sorted list of every registered item, used by the creator for auto completion.
function Framework.GetItemList()
    if itemList then return itemList end
    local list = {}
    for name, item in pairs(exports.ox_inventory:Items() or {}) do
        list[#list + 1] = { name = name, label = item.label or name }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    itemList = list
    return list
end

---@param src number
---@param name string
---@return number
function Framework.GetItemCount(src, name)
    return exports.ox_inventory:Search(src, 'count', name) or 0
end

---@param src number
---@param name string
---@param count number
function Framework.RemoveItem(src, name, count)
    return exports.ox_inventory:RemoveItem(src, name, count) and true or false
end

---Gives an item. When the player cannot carry it the item is dropped at their feet,
---so a reward that was rolled is never lost.
---@param src number
---@param name string
---@param count number
---@return boolean given, boolean dropped
function Framework.GiveItem(src, name, count)
    if exports.ox_inventory:CanCarryItem(src, name, count) then
        if exports.ox_inventory:AddItem(src, name, count) then
            return true, false
        end
    end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        exports.ox_inventory:CustomDrop('Heist', { { name, count } }, GetEntityCoords(ped))
        return true, true
    end
    return false, false
end
