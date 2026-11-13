-- Heist HUD (player interface opened at the NPC).
local function fetchHud()
    local data, err = lib.callback.await('heist_creator:getHud', false)
    if type(data) ~= 'table' then return nil, err end
    return data
end

function OpenHeistHud()
    if NUI.open then return end
    local data, err = fetchHud()
    if not data then
        Notify(err or L('not_ready'), 'error')
        return
    end
    NUI.Focus('hud')
    NUI.Send('hud:open', data)
end

function CloseHeistHud()
    if NUI.open ~= 'hud' then return end
    NUI.Focus(nil)
    NUI.Send('hud:close')
end

RegisterNUICallback('hud:refresh', function(_, cb)
    local data = fetchHud()
    cb({ ok = data ~= nil, data = data })
end)

RegisterNUICallback('hud:party', function(body, cb)
    local ok, result = lib.callback.await('heist_creator:party', false, body.action, body.target)
    cb({ ok = ok == true, result = result })
end)

RegisterNUICallback('hud:start', function(body, cb)
    local ok, err = lib.callback.await('heist_creator:startHeist', false, body.id)
    if ok then CloseHeistHud() end
    cb({ ok = ok == true, result = err })
end)

RegisterNUICallback('hud:cancel', function(_, cb)
    local ok, message = lib.callback.await('heist_creator:cancelHeist', false)
    cb({ ok = ok == true, result = message })
end)

-- Party changes pushed by the server while the HUD is open.
RegisterNetEvent('heist_creator:client:partyUpdate', function(party)
    NUI.Send('hud:party', party or false)
end)

RegisterNetEvent('heist_creator:client:invited', function(from, acceptCommand, declineCommand)
    Notify(L('party_invited', from, acceptCommand, declineCommand), 'info', 12000)
    NUI.Send('hud:invited')
end)
