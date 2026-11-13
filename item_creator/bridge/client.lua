-- item_creator bridge (client). This file lives INSIDE ox_inventory and is
-- installed by the item_creator resource.
if not lib then return end

local loaded, Items = pcall(require, 'modules.items.client')

if not loaded or type(Items) ~= 'table' then
    return warn('[item_creator] could not access the ox_inventory item list - bridge disabled')
end

local RESOURCE = GetCurrentResourceName()
local FILE = 'data/created_items.lua'

local function useExport(resource, export)
    return function(...)
        return exports[resource][export](nil, ...)
    end
end

---Same rules as newItem() in modules/items/shared.lua (client side).
---@param image? string data URI; without it the default web/images/<name>.png is used
local function register(name, definition, image)
    if type(name) ~= 'string' or type(definition) ~= 'table' then return end

    local data = lib.table.deepclone(definition)
    local previous = rawget(Items, name)

    data.name = name
    data.weight = data.weight or 0

    if data.close == nil then data.close = true end
    if data.stack == nil then data.stack = true end

    local clientData, serverData = data.client, data.server

    if not data.consume and ((clientData and (clientData.status or clientData.usetime or clientData.export))
        or (serverData and serverData.export)) then
        data.consume = 1
    end

    data.server = nil
    data.count = previous and previous.count or 0

    if clientData and clientData.export then
        data.export = useExport(string.strsplit('.', clientData.export))
    end

    if image then
        data.client = clientData or {}
        data.client.image = image
        data.image = image -- read by the inventory UI when it asks for unknown items
    end

    Items[name] = data
end

-- Items that existed when the server started.
do
    local content = LoadResourceFile(RESOURCE, FILE)
    local chunk = content and load(content, ('@@%s/%s'):format(RESOURCE, FILE), 't', {})
    local ok, result = pcall(chunk or function() return {} end)

    if ok and type(result) == 'table' then
        for name, definition in pairs(result) do
            pcall(register, name, definition)
        end
    end
end

-- Items created while the server is running.
RegisterNetEvent('ox_inventory:creator:items', function(list)
    if type(list) ~= 'table' then return end

    for i = 1, #list do
        local entry = list[i]
        if type(entry) == 'table' then
            pcall(register, entry.name, entry.definition, type(entry.image) == 'string' and entry.image or nil)
        end
    end
end)

RegisterNetEvent('ox_inventory:creator:heal', function(amount)
    if type(amount) ~= 'number' or amount <= 0 then return end

    local ped = cache.ped
    local maxHealth = GetEntityMaxHealth(ped)
    local gain = math.floor((maxHealth - 100) * math.min(amount, 100) / 100 + 0.5)

    SetEntityHealth(ped, math.min(maxHealth, GetEntityHealth(ped) + gain))
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('ox_inventory:creator:request')
end)
