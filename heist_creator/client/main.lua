-- Client entry point: relationships, shared NUI callbacks, police alert.
local GUARD_GROUP = GetHashKey('HEIST_CREATOR_GUARDS')
local PLAYER_GROUP = GetHashKey('PLAYER')

CreateThread(function()
    -- Relationships are local to every client, so each client sets them up.
    AddRelationshipGroup('HEIST_CREATOR_GUARDS')
    SetRelationshipBetweenGroups(5, GUARD_GROUP, PLAYER_GROUP)
    SetRelationshipBetweenGroups(5, PLAYER_GROUP, GUARD_GROUP)
    SetRelationshipBetweenGroups(0, GUARD_GROUP, GUARD_GROUP)
end)

-- Closes whichever page is open (ESC / close button).
RegisterNUICallback('close', function(_, cb)
    if NUI.open == 'hud' then
        CloseHeistHud()
    elseif NUI.open == 'creator' then
        CloseCreator()
    end
    cb({})
end)

-- Built-in police alert (see Config.PoliceAlert).
RegisterNetEvent('heist_creator:client:policeAlert', function(coords, heistName)
    if type(coords) ~= 'vector3' then return end
    Notify(L('police_alert', heistName), 'error', 10000)

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.PoliceAlert.blipSprite)
    SetBlipColour(blip, Config.PoliceAlert.blipColour)
    SetBlipScale(blip, 1.2)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('police_blip'))
    EndTextCommandSetBlipName(blip)

    SetTimeout(Config.PoliceAlert.blipSeconds * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- Never leave the cursor stuck when the resource restarts while a page is open.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and NUI.open then
        SetNuiFocus(false, false)
    end
end)
