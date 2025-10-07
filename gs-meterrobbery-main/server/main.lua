local QBCore = nil
local ESX = nil
local currentFramework = nil

local globalCooldown = 0
local playerCooldowns = {}
local meterCooldowns = {}

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

local function GetPlayerIdentifier(source)
    if currentFramework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.PlayerData.citizenid
        end
    elseif currentFramework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.identifier
        end
    end
    
    return tostring(source) 
end

local function CountPolice()
    local policeCount = 0
    
    if currentFramework == 'qb' then
        local players = QBCore.Functions.GetQBPlayers()
        for _, player in pairs(players) do
            for _, job in pairs(Config.Meters.police.jobs) do
                if player.PlayerData.job.name == job and player.PlayerData.job.onduty then
                    policeCount = policeCount + 1
                end
            end
        end
    elseif currentFramework == 'esx' then
        local players = ESX.GetPlayers()
        for _, playerId in ipairs(players) do
            local xPlayer = ESX.GetPlayerFromId(playerId)
            for _, job in pairs(Config.Meters.police.jobs) do
                if xPlayer.job.name == job then
                    policeCount = policeCount + 1
                end
            end
        end
    end
    
    return policeCount
end

local function RemoveItems(source, failed)
    if not Config.RequiredItems.enabled then return end
    
    if currentFramework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        
        for _, item in pairs(Config.RequiredItems.items) do
            if item.remove then
                local shouldRemove = failed or (math.random(1, 100) <= item.chance)
                if shouldRemove then
                    Player.Functions.RemoveItem(item.name, item.amount)
                    TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'remove', item.amount)
                end
            end
        end
    elseif currentFramework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return end
        
        for _, item in pairs(Config.RequiredItems.items) do
            if item.remove then
                local shouldRemove = failed or (math.random(1, 100) <= item.chance)
                if shouldRemove then
                    xPlayer.removeInventoryItem(item.name, item.amount)
                end
            end
        end
    end
end

local function GiveRewards(source)
    if currentFramework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        
        if Config.Rewards.money.enabled then
            local amount = math.random(Config.Rewards.money.minAmount, Config.Rewards.money.maxAmount)
            local moneyType = Config.Rewards.money.type
            
            if moneyType == 'cash' then
                Player.Functions.AddMoney('cash', amount)
            elseif moneyType == 'bank' then
                Player.Functions.AddMoney('bank', amount)
            elseif moneyType == 'black_money' or moneyType == 'crypto' then
                Player.Functions.AddMoney(moneyType, amount)
            end
        end
        
        if Config.Rewards.items.enabled then
            for _, item in pairs(Config.Rewards.items.possible) do
                if math.random(1, 100) <= item.chance then
                    local amount = math.random(item.min, item.max)
                    Player.Functions.AddItem(item.name, amount)
                    TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item.name], 'add', amount)
                end
            end
        end
    elseif currentFramework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return end
        
        if Config.Rewards.money.enabled then
            local amount = math.random(Config.Rewards.money.minAmount, Config.Rewards.money.maxAmount)
            local moneyType = Config.Rewards.money.type
            
            if moneyType == 'cash' then
                xPlayer.addMoney(amount)
            elseif moneyType == 'bank' then
                xPlayer.addAccountMoney('bank', amount)
            elseif moneyType == 'black_money' then
                xPlayer.addAccountMoney('black_money', amount)
            end
        end
        
        if Config.Rewards.items.enabled then
            for _, item in pairs(Config.Rewards.items.possible) do
                if math.random(1, 100) <= item.chance then
                    local amount = math.random(item.min, item.max)
                    xPlayer.addInventoryItem(item.name, amount)
                end
            end
        end
    end
end

local function CheckCooldowns(source, meterId)
    if not Config.Cooldown.enabled then return true end
    
    local currentTime = os.time()
    local playerId = GetPlayerIdentifier(source)
    
    if globalCooldown > currentTime then
        local remainingTime = globalCooldown - currentTime
        if Config.Cooldown.notify then
            TriggerClientEvent('gs-meterrobbery:client:cooldownNotify', source, 'global', remainingTime)
        end
        return false
    end
    
    if playerCooldowns[playerId] and playerCooldowns[playerId] > currentTime then
        local remainingTime = playerCooldowns[playerId] - currentTime
        if Config.Cooldown.notify then
            TriggerClientEvent('gs-meterrobbery:client:cooldownNotify', source, 'player', remainingTime)
        end
        return false
    end
    
    if meterCooldowns[meterId] and meterCooldowns[meterId] > currentTime then
        local remainingTime = meterCooldowns[meterId] - currentTime
        if Config.Cooldown.notify then
            TriggerClientEvent('gs-meterrobbery:client:cooldownNotify', source, 'meter', remainingTime)
        end
        return false
    end
    
    return true
end


local function SetCooldowns(source, meterId)
    local currentTime = os.time()
    local playerId = GetPlayerIdentifier(source)
    

    globalCooldown = currentTime + Config.Cooldown.global
    
    playerCooldowns[playerId] = currentTime + Config.Cooldown.player
    
    meterCooldowns[meterId] = currentTime + Config.Cooldown.meter
    
    if Config.Debug then
        print('[gs-meterrobbery] Cooldowns set - Global: ' .. globalCooldown .. ', Player: ' .. playerCooldowns[playerId] .. ', Meter: ' .. meterCooldowns[meterId])
    end
end

CreateThread(function()
    while true do
        Wait(60000) 
        local currentTime = os.time()
        
        for playerId, cooldownTime in pairs(playerCooldowns) do
            if cooldownTime < currentTime then
                playerCooldowns[playerId] = nil
            end
        end
        
        for meterId, cooldownTime in pairs(meterCooldowns) do
            if cooldownTime < currentTime then
                meterCooldowns[meterId] = nil
            end
        end
    end
end)

RegisterNetEvent('gs-meterrobbery:server:checkPoliceCount', function()
    local src = source
    local policeCount = CountPolice()
    
    TriggerClientEvent('gs-meterrobbery:client:receivePoliceCount', src, policeCount)
end)

RegisterNetEvent('gs-meterrobbery:server:removeItems', function(failed)
    local src = source
    RemoveItems(src, failed)
end)

RegisterNetEvent('gs-meterrobbery:server:giveRewards', function()
    local src = source
    GiveRewards(src)
end)

RegisterNetEvent('gs-meterrobbery:server:notifyPolice', function(coords)
    if not Config.Meters.police.required then return end
    
    if currentFramework == 'qb' then
        local players = QBCore.Functions.GetQBPlayers()
        for _, player in pairs(players) do
            for _, job in pairs(Config.Meters.police.jobs) do
                if player.PlayerData.job.name == job and player.PlayerData.job.onduty then
                    TriggerClientEvent('gs-meterrobbery:client:policeAlert', player.PlayerData.source, coords)
                end
            end
        end
    elseif currentFramework == 'esx' then
        local players = ESX.GetPlayers()
        for _, playerId in ipairs(players) do
            local xPlayer = ESX.GetPlayerFromId(playerId)
            for _, job in pairs(Config.Meters.police.jobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('gs-meterrobbery:client:policeAlert', playerId, coords)
                end
            end
        end
    end
end)

RegisterNetEvent('gs-meterrobbery:server:checkCooldown', function(meterId)
    local src = source
    local canRob = CheckCooldowns(src, meterId)
    
    TriggerClientEvent('gs-meterrobbery:client:cooldownResult', src, canRob)
    
    if canRob then
        SetCooldowns(src, meterId)
    end
end)

CreateThread(function()
    if not InitializeFramework() then return end
    
    if Config.Debug then
        print('[gs-meterrobbery] Server initialized with framework: ' .. currentFramework)
    end
end)