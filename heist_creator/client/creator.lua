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
local function cameraRaycast(distance, ignore)
    local rotation = GetGameplayCamRot(2)
    local origin = GetGameplayCamCoord()
    local rx, rz = math.rad(rotation.x), math.rad(rotation.z)
    local cosX = math.abs(math.cos(rx))
    local direction = vector3(-math.sin(rz) * cosX, math.cos(rz) * cosX, math.sin(rx))
    local target = origin + direction * distance

    local handle = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z,
        target.x, target.y, target.z, 17, ignore or cache.ped or PlayerPedId(), 4)
    local _, hit, coords, _, entity = GetShapeTestResult(handle)
    return hit == 1 or hit == true, coords, entity
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
-- Props: live preview, placement with a ghost object, picking world objects
---------------------------------------------------------------------------
local preview = nil -- { object = entity } shown while the prop picker is open

---@param name string
---@return number? hash nil when the model cannot be used
local function loadPropModel(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    if not lib.requestModel(hash, 8000) then return nil end
    return hash
end

local function clearPreview()
    if not preview then return end
    if DoesEntityExist(preview.object) then DeleteEntity(preview.object) end
    if preview.camera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(preview.camera, false)
    end
    preview = nil
end

---Shows the model on its own, filling the screen: it is put high in the sky
---(nothing in front of or behind it), a camera is framed to its size and it
---is lit, so even a tiny prop is easy to see at any time of day.
local function showPreview(name)
    clearPreview()
    local hash = loadPropModel(name)
    if not hash then return false end

    local ped = cache.ped or PlayerPedId()
    local min, max = GetModelDimensions(hash)
    local size = math.max(0.05, #(max - min))
    local base = GetEntityCoords(ped) + vector3(0.0, 0.0, 150.0)

    local object = CreateObjectNoOffset(hash, base.x, base.y, base.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not object or object == 0 then return false end

    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)

    -- Aim at the middle of the model; the distance follows its size so that a
    -- coin and a container both fill about the same part of the screen.
    local centre = base + vector3(0.0, 0.0, (min.z + max.z) / 2)
    local distance = math.max(0.35, size * 1.35)
    local eye = centre + vector3(0.0, -distance, distance * 0.35)

    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camera, eye.x, eye.y, eye.z)
    PointCamAtCoord(camera, centre.x, centre.y, centre.z)
    SetCamFov(camera, 40.0)
    SetCamNearClip(camera, 0.02)
    SetCamActive(camera, true)
    RenderScriptCams(true, false, 0, true, true)

    local current = { object = object, camera = camera }
    preview = current

    CreateThread(function()
        local heading = 0.0
        local reach = distance * 4.0 + 4.0
        while preview == current and DoesEntityExist(object) do
            heading = (heading + 0.5) % 360.0
            SetEntityHeading(object, heading)
            -- Two lights (camera side and opposite side) so it is clear at night too.
            DrawLightWithRange(eye.x, eye.y, eye.z + distance * 0.5, 255, 255, 255, reach, 4.0)
            DrawLightWithRange(centre.x + distance, centre.y + distance, centre.z + distance, 255, 255, 255, reach, 2.0)
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
    return true, Utils.Round(size, 1)
end

---------------------------------------------------------------------------
-- The props of the heist being edited are shown in the world (local copies),
-- so new ones can be placed around them without overlapping.
---------------------------------------------------------------------------
local shown = {} -- [key] = { object, index, coords }

local function shownKey(prop)
    local c = prop.coords
    return ('%s|%.2f|%.2f|%.2f|%.1f'):format(prop.model, c.x, c.y, c.z, c.w or 0.0)
end

local function removeShown(key)
    local entry = shown[key]
    if entry and DoesEntityExist(entry.object) then DeleteEntity(entry.object) end
    shown[key] = nil
end

---@param props? table[] list of { model, coords }; nil or empty removes everything
---@param exclude? number 1-based index of a prop that must not be shown (it is being moved)
local function syncShownProps(props, exclude)
    local wanted = {}
    for i = 1, #(props or {}) do
        local prop = props[i]
        if i ~= exclude and type(prop) == 'table' and type(prop.model) == 'string' and type(prop.coords) == 'table'
            and tonumber(prop.coords.x) and tonumber(prop.coords.y) and tonumber(prop.coords.z) then
            wanted[shownKey(prop)] = { prop = prop, index = i }
        end
    end

    for key in pairs(shown) do
        if not wanted[key] then removeShown(key) end
    end

    for key, entry in pairs(wanted) do
        if shown[key] then
            shown[key].index = entry.index
        else
            local hash = loadPropModel(entry.prop.model)
            if hash then
                local c = entry.prop.coords
                local object = CreateObjectNoOffset(hash, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false)
                SetModelAsNoLongerNeeded(hash)
                if object and object ~= 0 then
                    SetEntityHeading(object, (tonumber(c.w) or 0.0) + 0.0)
                    FreezeEntityPosition(object, true)
                    local _, max = GetModelDimensions(hash)
                    shown[key] = { object = object, index = entry.index, top = math.max(0.0, max.z) }
                end
            end
        end
    end
end

---Removes the displayed props (creator closed for good, heist started, resource stopped).
function ClearCreatorProps()
    syncShownProps(nil)
end

-- Number above every displayed prop.
CreateThread(function()
    while true do
        if next(shown) then
            local origin = GetEntityCoords(cache.ped or PlayerPedId())
            for _, entry in pairs(shown) do
                if DoesEntityExist(entry.object) then
                    local c = GetEntityCoords(entry.object)
                    if #(origin - c) < 30.0 then
                        SetDrawOrigin(c.x, c.y, c.z + entry.top + 0.25, 0)
                        SetTextScale(0.32, 0.32)
                        SetTextFont(0)
                        SetTextColour(245, 185, 66, 235)
                        SetTextOutline()
                        SetTextCentre(true)
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName(('#%d'):format(entry.index))
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

---Lets the admin put a see-through copy of the prop where it should spawn.
---@param name string
---@param start? { w: number } previous placement (keeps its heading)
---@return table? coords x, y, z, w (heading) and h (height of the model above its origin)
local function placeProp(name, start)
    local hash = loadPropModel(name)
    if not hash then
        Notify(L('preview_invalid'), 'error')
        return nil
    end

    local ped = cache.ped or PlayerPedId()
    local min, max = GetModelDimensions(hash)
    local spawn = GetEntityCoords(ped)
    local object = CreateObjectNoOffset(hash, spawn.x, spawn.y, spawn.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not object or object == 0 then return nil end

    SetEntityAlpha(object, 190, false)
    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)

    local heading = start and tonumber(start.w) or GetEntityHeading(ped)
    local lift = 0.0
    local result

    lib.showTextUI(L('place_help'), { position = 'top-center' })
    while true do
        Wait(0)
        DisablePlayerFiring(cache.playerId or PlayerId(), true)
        for _, control in ipairs({ 24, 25, 172, 173, 174, 175, 47 }) do DisableControlAction(0, control, true) end

        if IsDisabledControlPressed(0, 174) then heading = (heading + 1.5) % 360.0 end
        if IsDisabledControlPressed(0, 175) then heading = (heading - 1.5) % 360.0 end
        if IsDisabledControlPressed(0, 172) then lift = lift + 0.01 end
        if IsDisabledControlPressed(0, 173) then lift = lift - 0.01 end
        if IsDisabledControlJustReleased(0, 47) then lift = 0.0 end

        local hit, coords = cameraRaycast(80.0, object)
        if hit then
            -- The bottom of the model rests on the surface that is aimed at.
            SetEntityCoordsNoOffset(object, coords.x, coords.y, coords.z - min.z + lift, false, false, false)
        end
        SetEntityHeading(object, heading)

        if IsControlJustReleased(0, 38) then
            local final = GetEntityCoords(object)
            result = {
                x = Utils.Round(final.x, 2),
                y = Utils.Round(final.y, 2),
                z = Utils.Round(final.z, 2),
                w = Utils.Round(heading, 1),
                h = Utils.Round(math.max(0.0, max.z), 2),
            }
            break
        end
        if IsControlJustReleased(0, 177) then break end
    end

    lib.hideTextUI()
    DeleteEntity(object)
    return result
end

---Lets the admin aim at an object that already exists in the world (a safe in
---an MLO, an ATM...) and returns a position just above it.
local function pickObject()
    local result
    local shown

    while true do
        Wait(0)
        DisablePlayerFiring(cache.playerId or PlayerId(), true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)

        local hit, _, entity = cameraRaycast(60.0)
        local isObject = hit and entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 3

        local text = isObject and ('%s\n%s'):format(GetEntityArchetypeName(entity) or '?', L('object_help')) or L('object_none')
        if text ~= shown then
            shown = text
            lib.showTextUI(text, { position = 'top-center' })
        end

        if isObject then
            local coords = GetEntityCoords(entity)
            local _, max = GetModelDimensions(GetEntityModel(entity))
            local top = coords.z + math.max(0.0, max.z)
            DrawMarker(0, coords.x, coords.y, top + 0.35, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                0.25, 0.25, 0.25, 245, 185, 66, 220, true, true, 2, false, nil, nil, false)

            if IsControlJustReleased(0, 38) then
                result = {
                    x = Utils.Round(coords.x, 2),
                    y = Utils.Round(coords.y, 2),
                    z = Utils.Round(top + 0.05, 2),
                    w = Utils.Round(GetEntityHeading(entity), 1),
                }
                break
            end
        end

        if IsControlJustReleased(0, 177) then break end
    end

    lib.hideTextUI()
    return result
end

---Runs a mode that needs the game view: hides the creator, gives back control.
local function withoutUi(action)
    NUI.Send('creator:hide')
    NUI.Focus(nil)
    local ok, result = pcall(action)
    NUI.Focus('creator')
    NUI.Send('creator:show')
    if not ok then print(('[Heist Creator] %s'):format(result)) end
    return ok and result or nil
end

RegisterNUICallback('creator:propPreview', function(body, cb)
    if NUI.open ~= 'creator' then return cb({ ok = false }) end
    local ok, size = showPreview(body.model)
    cb({ ok = ok == true, size = size })
end)

RegisterNUICallback('creator:propPreviewStop', function(_, cb)
    clearPreview()
    cb({})
end)

RegisterNUICallback('creator:placeProp', function(body, cb)
    if NUI.open ~= 'creator' then return cb({ ok = false }) end
    clearPreview()
    -- A prop that is being moved is taken out of the world while it is carried.
    if type(body.props) == 'table' then syncShownProps(body.props, tonumber(body.moving)) end
    local coords = withoutUi(function() return placeProp(body.model, body.coords) end)
    cb({ ok = coords ~= nil, coords = coords })
end)

RegisterNUICallback('creator:showProps', function(body, cb)
    if NUI.open == 'creator' then
        syncShownProps(body.show and body.props or nil)
    end
    cb({})
end)

RegisterNUICallback('creator:pickObject', function(_, cb)
    if NUI.open ~= 'creator' then return cb({ ok = false }) end
    local coords = withoutUi(pickObject)
    cb({ ok = coords ~= nil, coords = coords })
end)

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
forward('creator:getDoors', 'heist_creator:admin:getDoors', function() end)
forward('creator:saveTaxonomy', 'heist_creator:admin:saveTaxonomy', function(body) return body.genres, body.tags end)
forward('creator:saveNpcs', 'heist_creator:admin:saveNpcs', function(body) return body.npcs end)

function CloseCreator()
    clearPreview()
    if NUI.open ~= 'creator' then return end
    NUI.Focus(nil)
    NUI.Send('creator:close')
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearPreview()
        ClearCreatorProps()
    end
end)
