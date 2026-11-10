-- Heist Creator (admin). The client only collects input: every action is
-- validated again on the server, which also checks the admin permission.
local function playerPosition()
    local ped = cache.ped or PlayerPedId()
    local coords = GetEntityCoords(ped)
    return {
        x = Utils.Round(coords.x, 2),
        y = Utils.Round(coords.y, 2),
        z = Utils.Round(coords.z, 2),
        w = Utils.Round(GetEntityHeading(ped), 1),
    }
end

local function openCreator()
    if NUI.open then return end
    local data, err = lib.callback.await('heist_creator:admin:getData', false)
    if type(data) ~= 'table' then
        Notify(err or L('no_permission'), 'error')
        return
    end
    NUI.Focus('creator')
    NUI.Send('creator:open', data)
end

RegisterNetEvent('heist_creator:client:openCreator', openCreator)

---------------------------------------------------------------------------
-- Position picking with the camera
---------------------------------------------------------------------------
local function cameraRaycast(distance)
    local rotation = GetGameplayCamRot(2)
    local origin = GetGameplayCamCoord()
    local rx, rz = math.rad(rotation.x), math.rad(rotation.z)
    local cosX = math.abs(math.cos(rx))
    local direction = vector3(-math.sin(rz) * cosX, math.cos(rz) * cosX, math.sin(rx))
    local target = origin + direction * distance

    local handle = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z,
        target.x, target.y, target.z, 17, cache.ped or PlayerPedId(), 4)
    local _, hit, coords = GetShapeTestResult(handle)
    return hit == 1 or hit == true, coords
end

---Lets the admin aim at a spot. Returns nil when cancelled.
local function pickPosition()
    local result
    lib.showTextUI(L('picker_help'), { position = 'top-center' })

    while true do
        Wait(0)
        DisablePlayerFiring(cache.playerId or PlayerId(), true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)

        local hit, coords = cameraRaycast(150.0)
        if hit then
            DrawMarker(28, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.15, 0.15, 0.15, 245, 185, 66, 200, false, false, 2, false, nil, nil, false)
            DrawMarker(1, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.8, 0.8, 0.25, 245, 185, 66, 90, false, false, 2, false, nil, nil, false)

            if IsControlJustReleased(0, 38) then
                -- Stored coordinates are "standing" coordinates (ground + 1.0),
                -- the same as the position of a player standing on that spot.
                result = {
                    x = Utils.Round(coords.x, 2),
                    y = Utils.Round(coords.y, 2),
                    z = Utils.Round(coords.z + 1.0, 2),
                    w = Utils.Round(GetEntityHeading(cache.ped or PlayerPedId()), 1),
                }
                break
            end
        end

        if IsControlJustReleased(0, 177) then break end
    end

    lib.hideTextUI()
    return result
end

---------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------
RegisterNUICallback('creator:getPosition', function(_, cb)
    cb(playerPosition())
end)

RegisterNUICallback('creator:pickPosition', function(_, cb)
    if NUI.open ~= 'creator' then return cb({ ok = false }) end
    NUI.Send('creator:hide')
    NUI.Focus(nil)
    local coords = pickPosition()
    NUI.Focus('creator')
    NUI.Send('creator:show')
    cb({ ok = coords ~= nil, coords = coords })
end)

RegisterNUICallback('creator:teleport', function(body, cb)
    local x, y, z = tonumber(body.x), tonumber(body.y), tonumber(body.z)
    if x and y and z then
        local ped = cache.ped or PlayerPedId()
        SetEntityCoords(ped, x, y, z - 1.0, false, false, false, false)
        if tonumber(body.w) then SetEntityHeading(ped, tonumber(body.w) + 0.0) end
    end
    cb({})
end)

---Forwards a creator action to the server and returns `{ ok, result }`.
local function forward(name, callbackName, getArgs)
    RegisterNUICallback(name, function(body, cb)
        local ok, result = lib.callback.await(callbackName, false, getArgs(body))
        cb({ ok = ok == true, result = result })
    end)
end

forward('creator:save', 'heist_creator:admin:save', function(body) return body.heist end)
forward('creator:delete', 'heist_creator:admin:delete', function(body) return body.id end)
forward('creator:toggle', 'heist_creator:admin:toggle', function(body) return body.id, body.enabled end)
forward('creator:resetCooldown', 'heist_creator:admin:resetCooldown', function(body) return body.id end)
forward('creator:saveNpcs', 'heist_creator:admin:saveNpcs', function(body) return body.npcs end)

function CloseCreator()
    if NUI.open ~= 'creator' then return end
    NUI.Focus(nil)
    NUI.Send('creator:close')
end
