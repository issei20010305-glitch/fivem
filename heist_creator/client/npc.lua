-- Heist HUD NPCs. Peds are local and only exist while the player is close.
local npcs = {} -- { point, ped, blip }

local function removeAll()
    for i = 1, #npcs do
        local npc = npcs[i]
        npc.point:remove()
        if npc.ped and DoesEntityExist(npc.ped) then
            exports.ox_target:removeLocalEntity(npc.ped, { 'heist_creator:hud', 'heist_creator:finish' })
            DeleteEntity(npc.ped)
        end
        if npc.blip and DoesBlipExist(npc.blip) then RemoveBlip(npc.blip) end
    end
    npcs = {}
end

local function spawnPed(npc, data)
    local model = GetHashKey(data.model)
    if not IsModelInCdimage(model) then
        model = GetHashKey(Config.Npc.defaultModel)
    end
    if not lib.requestModel(model, 10000) then return end

    local ped = CreatePed(4, model, data.x, data.y, data.z - 1.0, data.w, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    if Config.Npc.scenario and Config.Npc.scenario ~= '' then
        TaskStartScenarioInPlace(ped, Config.Npc.scenario, 0, true)
    end

    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'heist_creator:hud',
            icon = 'fa-solid fa-mask',
            label = L('npc_target'),
            distance = Config.Npc.targetDistance,
            onSelect = function() OpenHeistHud() end,
        },
        {
            name = 'heist_creator:finish',
            icon = 'fa-solid fa-flag-checkered',
            label = L('extract_label'),
            distance = Config.Npc.targetDistance,
            canInteract = function() return CanFinishHeistAt(data.x, data.y) end,
            onSelect = function() FinishHeist() end,
        },
    })
    npc.ped = ped
end

---@param list table[]
local function setNpcs(list)
    removeAll()
    for i = 1, #list do
        local data = list[i]
        local npc = {}

        npc.point = lib.points.new({
            coords = vector3(data.x, data.y, data.z),
            distance = Config.Npc.spawnDistance,
        })

        function npc.point:onEnter()
            if not npc.ped then spawnPed(npc, data) end
        end

        function npc.point:onExit()
            if npc.ped then
                exports.ox_target:removeLocalEntity(npc.ped, { 'heist_creator:hud', 'heist_creator:finish' })
                if DoesEntityExist(npc.ped) then DeleteEntity(npc.ped) end
                npc.ped = nil
            end
        end

        local blipCfg = Config.Npc.blip
        if blipCfg.enabled then
            local blip = AddBlipForCoord(data.x, data.y, data.z)
            SetBlipSprite(blip, blipCfg.sprite)
            SetBlipColour(blip, blipCfg.colour)
            SetBlipScale(blip, blipCfg.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(blipCfg.label)
            EndTextCommandSetBlipName(blip)
            npc.blip = blip
        end

        npcs[i] = npc
    end
end

RegisterNetEvent('heist_creator:client:setNpcs', function(list)
    if type(list) == 'table' then setNpcs(list) end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    -- The server may still be loading its data right after a restart.
    for _ = 1, 30 do
        local list = lib.callback.await('heist_creator:getNpcs', false)
        if type(list) == 'table' then
            setNpcs(list)
            return
        end
        Wait(2000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then removeAll() end
end)
