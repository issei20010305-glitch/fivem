-- Admin item spawner UI. The item list (with pictures) comes from
-- ox_inventory on this client; giving is done and checked by the server.
local isOpen = false
local cache = { items = nil, created = -1, at = 0 } -- the list is rebuilt at most once a minute

---Every ox_inventory item, including the ones made with item_creator.
---@param created table<string, boolean>
local function buildItems(created)
    local imagePath = GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images')
    local list = {}

    local ok, items = pcall(function() return exports.ox_inventory:Items() end)
    if not ok or type(items) ~= 'table' then return list end

    for name, item in pairs(items) do
        if type(item) == 'table' and type(name) == 'string' and item.name == name then
            local image = type(item.client) == 'table' and item.client.image or item.image
            local kind = item.weapon and 'weapon' or item.ammo and 'ammo'
                or (item.component or item.tint) and 'part' or 'item'

            list[#list + 1] = {
                name = name,
                label = item.label or name,
                description = item.description,
                weight = item.weight or 0,
                stack = item.stack ~= false,
                kind = kind,
                created = created[name] == true,
                image = type(image) == 'string' and image or ('%s/%s.png'):format(imagePath, name),
            }
        end
    end

    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return list
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('item_spawner:open', function()
    if isOpen then return end

    local data = lib.callback.await('item_spawner:getData', false)
    if type(data) ~= 'table' then
        lib.notify({ type = 'error', description = 'この操作を行う権限がありません。' })
        return
    end

    local created = {}
    for i = 1, #data.created do created[data.created[i]] = true end

    -- Reading every item from ox_inventory is not free, so reuse the list unless
    -- item_creator items changed or it is older than a minute.
    local now = GetGameTimer()
    if not cache.items or cache.created ~= #data.created or now - cache.at > 60000 then
        cache.items = buildItems(created)
        cache.created = #data.created
        cache.at = now
    end

    data.items = cache.items
    data.created = nil

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('give', function(body, cb)
    local ok, message = lib.callback.await('item_spawner:give', false, body.name, body.amount, body.target)
    cb({ ok = ok == true, message = message })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)
