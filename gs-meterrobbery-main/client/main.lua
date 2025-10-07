local QBCore = nil
local ESX = nil
local PlayerData = {}
local isLoggedIn = false
local currentFramework = nil
local meterModels = {}
local canRobMeter = true


local function InitializeFramework()
    if Config.Framework == 'auto' or Config.Framework == 'qb' then
        if GetResourceState('qb-core') ~= 'missing' then
            QBCore = exports['qb-core']:GetCoreObject()
            if QBCore then
                currentFramework = 'qb'
                return true
            end
        end
    end
    
    if Config.Framework == 'auto' or Config.Framework == 'esx' then
        if GetResourceState('es_extended') ~= 'missing' then
            ESX = exports['es_extended']:getSharedObject()
            if ESX then
                currentFramework = 'esx'
                return true
            end
        end
    end
    
    print('[gs-meterrobbery] No compatible framework found. Please install QBCore or ESX.')
    return false
end

local function InitializeTarget()
    if Config.Target == 'auto' or Config.Target == 'ox' then
        if GetResourceState('ox_target') ~= 'missing' then
            Config.Target = 'ox'
            return true
        end
    end
    
    if Config.Target == 'auto' or Config.Target == 'qb' then
        if GetResourceState('qb-target') ~= 'missing' then
            Config.Target = 'qb'
            return true
        end
    end
    
    print('[gs-meterrobbery] No compatible target system found. Please install ox_target or qb-target.')
    return false
end

local function InitializePlayerData()
    if currentFramework == 'qb' then
        PlayerData = QBCore.Functions.GetPlayerData()
        isLoggedIn = true
        
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            PlayerData = QBCore.Functions.GetPlayerData()
            isLoggedIn = true
        end)
        
        RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
            PlayerData = {}
            isLoggedIn = false
        end)
        
        RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
            PlayerData = data
        end)
    elseif currentFramework == 'esx' then
        ESX.PlayerData = ESX.GetPlayerData()
        PlayerData = ESX.PlayerData
        isLoggedIn = true
        
        RegisterNetEvent('esx:playerLoaded', function(xPlayer)
            ESX.PlayerData = xPlayer
            PlayerData = xPlayer
            isLoggedIn = true
        end)
        
        RegisterNetEvent('esx:setJob', function(job)
            ESX.PlayerData.job = job
            PlayerData.job = job
        end)
    end
end

local function HasRequiredItems()
    if not Config.RequiredItems.enabled then return true end
    
    local hasItems = true
    
    if currentFramework == 'qb' then
        for _, item in pairs(Config.RequiredItems.items) do
            local hasItem = QBCore.Functions.HasItem(item.name, item.amount)
            if not hasItem then
                hasItems = false
                break
            end
        end
    elseif currentFramework == 'esx' then
        for _, item in pairs(Config.RequiredItems.items) do
            local hasItem = false
            for _, playerItem in pairs(PlayerData.inventory) do
                if playerItem.name == item.name and playerItem.count >= item.amount then
                    hasItem = true
                    break
                end
            end
            if not hasItem then
                hasItems = false
                break
            end
        end
    end
    
    return hasItems
end

local policeCount = 0

RegisterNetEvent('gs-meterrobbery:client:receivePoliceCount', function(count)
    policeCount = count
end)

local function IsEnoughPoliceOnline()
    if not Config.Meters.police.required or Config.Meters.police.minimum <= 0 then return true end
    
    TriggerServerEvent('gs-meterrobbery:server:checkPoliceCount')
    
    Wait(100)
    
    return policeCount >= Config.Meters.police.minimum
end

local function SendDispatchAlert(coords)
    if not Config.Dispatch.enabled then return end
    
    local timeElapsed = GetGameTimer() - (lastDispatchTime or 0)
    if timeElapsed < Config.Dispatch.cooldown then return end
    
    lastDispatchTime = GetGameTimer()
    
    if Config.Dispatch.system == 'ps' then
        if GetResourceState('ps-dispatch') ~= 'missing' then
            exports['ps-dispatch']:MeterRobbery(coords)
        end
    elseif Config.Dispatch.system == 'cd' then
        if GetResourceState('cd_dispatch') ~= 'missing' then
            local data = {
                title = _U('dispatch_title'),
                description = _U('dispatch_desc'),
                coords = coords,
                blip = {
                    sprite = 47,
                    color = 1,
                    scale = 1.0,
                    label = _U('meter_robbery')
                }
            }
            exports['cd_dispatch']:SendNotification(data)
        end
    elseif Config.Dispatch.system == 'custom' then
        TriggerServerEvent('gs-meterrobbery:server:notifyPolice', coords)
    end
end

local function PlayRobberyAnimation()
    local ped = PlayerPedId()
    local animDict = Config.Meters.animation.dict
    local animName = Config.Meters.animation.anim
    local animFlag = Config.Meters.animation.flag
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
    end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, animFlag, 0, false, false, false)
end

local function StopRobberyAnimation()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
end

local function StartMinigame()
    local success = false
    local minigameType = Config.Minigame.type
    local difficulty = Config.Minigame.difficulty
    
    if minigameType == 'circle' then
        local circles = Config.Minigame.circle[difficulty].circles
        success = lib.skillCheck({'easy', 'medium', 'medium'}, {'w', 'a', 's', 'd'})
    elseif minigameType == 'maze' then
        local size = Config.Minigame.maze[difficulty].size
        success = exports['ox_lib']:maze({
            size = size
        })
    elseif minigameType == 'lockpick' then
        local pins = Config.Minigame.lockpick[difficulty].pins
        local difficulties = {}
        for i=1, pins do
            table.insert(difficulties, 'medium') 
        success = lib.skillCheck(difficulties, {'w', 'a', 's', 'd'})
    end
    
    return success
end


RegisterNetEvent('gs-meterrobbery:client:cooldownNotify', function(cooldownType, remainingTime)
    if not Config.Cooldown.notify then return end
    
    local message = ''
    
    if cooldownType == 'global' then
        message = _U('global_cooldown')
    elseif cooldownType == 'player' then
        message = _U('player_cooldown')
    elseif cooldownType == 'meter' then
        message = _U('meter_cooldown')
    end
    
    if remainingTime then
        message = message .. ' ' .. string.format(_U('cooldown_remaining'), remainingTime)
    end
    
    lib.notify({
        title = _U('meter_robbery'),
        description = message,
        type = 'error'
    })
end)


RegisterNetEvent('gs-meterrobbery:client:cooldownResult', function(result)
    canRobMeter = result
end)

local function ProcessMeterRobbery(entity)
    if not IsEnoughPoliceOnline() then
        lib.notify({
            title = _U('meter_robbery'),
            description = _U('police_required'),
            type = 'error'
        })
        return
    end
    
    if not HasRequiredItems() then
        lib.notify({
            title = _U('meter_robbery'),
            description = _U('missing_item'),
            type = 'error'
        })
        return
    end
    
    local coords = GetEntityCoords(entity)
    local meterId = tostring(NetworkGetNetworkIdFromEntity(entity))
    

    TriggerServerEvent('gs-meterrobbery:server:checkCooldown', meterId)
    

    Wait(100)
    
    if not canRobMeter then
        return 
        
    end
    
    PlayRobberyAnimation()
    
    lib.notify({
        title = _U('meter_robbery'),
        description = _U('minigame_start'),
        type = 'inform'
    })
    
    local minigameSuccess = StartMinigame()
    
    StopRobberyAnimation()
    
    if not minigameSuccess then
        lib.notify({
            title = _U('meter_robbery'),
            description = _U('minigame_failed'),
            type = 'error'
        })
        
        SendDispatchAlert(coords)
        
        TriggerServerEvent('gs-meterrobbery:server:removeItems', true)
        
        return
    end
    
    local successChance = Config.Meters.successChance
    local randomChance = math.random(1, 100)
    
    if randomChance <= successChance then
        lib.notify({
            title = _U('meter_robbery'),
            description = _U('meter_robbed'),
            type = 'success'
        })
        
        SendDispatchAlert(coords)
        
        TriggerServerEvent('gs-meterrobbery:server:removeItems', false)
        
        TriggerServerEvent('gs-meterrobbery:server:giveRewards')
        
        SetEntityRotation(entity, GetEntityRotation(entity) + vector3(0, 45.0, 0), 2, true)
    else
        lib.notify({
            title = _U('meter_robbery'),
            description = _U('meter_failed'),
            type = 'error'
        })
        
        SendDispatchAlert(coords)
        
        TriggerServerEvent('gs-meterrobbery:server:removeItems', true)
    end
end

local function InitializeMeterModels()
    for _, model in pairs(Config.Meters.models) do
        table.insert(meterModels, GetHashKey(model))
    end
end

CreateThread(function()
    if not InitializeFramework() then return end
    
    InitializePlayerData()
    
    if not InitializeTarget() then return end
    
    InitializeMeterModels()
    
    if Config.Debug then
        print('[gs-meterrobbery] Initialized with framework: ' .. currentFramework)
        print('[gs-meterrobbery] Using target system: ' .. Config.Target)
    end
end)

exports('ProcessMeterRobbery', ProcessMeterRobbery)

exports('GetMeterModels', function()
    return meterModels
end)