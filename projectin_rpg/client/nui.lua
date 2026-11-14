--[[ NUI ブリッジ ]]
NUI = { open = false }

function NUI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function NUI.Open(screen, data)
    NUI.open = true
    SetNuiFocus(true, true)
    NUI.Send('open', { screen = screen, data = data })
end

function NUI.Close()
    NUI.open = false
    SetNuiFocus(false, false)
    NUI.Send('close', {})
end

function NUI.Toast(message, kind, duration)
    NUI.Send('toast', { message = message, type = kind or 'info', duration = duration or 5000 })
end

-- NUIから呼べるサーバーコールバック (サーバー側で全て再検証されます)
local allowed = {
    getProfile = true, chooseRole = true, getInventory = true, invMove = true, invDiscard = true, invUse = true,
    invClaimOverflow = true, party = true, entryCheck = true, enterDungeon = true, raidRegister = true, leaveRun = true,
    admin = true, getEvents = true,
}

RegisterNUICallback('request', function(body, cb)
    local name = body and body.name
    if not allowed[name] then return cb({ ok = false, error = '不正なリクエスト' }) end
    local args = type(body.args) == 'table' and body.args or {}
    local a, b = lib.callback.await('projectin_rpg:' .. name, false, table.unpack(args))
    if a == false then return cb({ ok = false, error = b or '失敗しました' }) end
    if a == nil and b ~= nil then return cb({ ok = false, error = b }) end
    cb({ ok = true, data = (b ~= nil and a == true) and b or a, message = (a == true and type(b) == 'string') and b or nil })
end)

RegisterNUICallback('close', function(_, cb)
    NUI.Close()
    cb({})
end)

RegisterNUICallback('setFocus', function(body, cb)
    SetNuiFocus(body.focus == true, body.focus == true)
    NUI.open = body.focus == true
    cb({})
end)

RegisterNetEvent('projectin_rpg:client:toast', function(data)
    NUI.Send('toast', data)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and NUI.open then SetNuiFocus(false, false) end
end)
