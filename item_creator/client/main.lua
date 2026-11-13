-- Item Creator (admin UI). The server validates and performs everything.
local isOpen = false

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('item_creator:open', function()
    if isOpen then return end
    local data, err = lib.callback.await('item_creator:getData', false)
    if type(data) ~= 'table' then
        lib.notify({ type = 'error', description = err or '権限がありません。', duration = 8000 })
        return
    end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('create', function(body, cb)
    local ok, result = lib.callback.await('item_creator:create', false, body)
    cb({ ok = ok == true, result = result })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)
