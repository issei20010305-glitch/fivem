-- Entry point: initialisation, callbacks, commands and lifecycle events.
local ready = false
local lastRequest = {} -- [src][name] = game timer of the last request (rate limiting)

local function notify(src, message, kind)
    TriggerClientEvent('heist_creator:client:notify', src, message, kind or 'info')
end

---Registers an ox_lib callback with rate limiting and an optional admin check.
---@param name string
---@param handler fun(src: number, ...): ...
---@param adminOnly? boolean
local function register(name, handler, adminOnly)
    lib.callback.register(('heist_creator:%s'):format(name), function(src, ...)
        if not ready then return false, L('not_ready') end

        local now = GetGameTimer()
        local requests = lastRequest[src]
        if not requests then
            requests = {}
            lastRequest[src] = requests
        end
        if requests[name] and now - requests[name] < Config.Security.rateLimitMs then
            return false, L('too_fast')
        end
        requests[name] = now

        if adminOnly and not Framework.IsAdmin(src) then
            print(('[Heist Creator] player %s tried to use admin action "%s" without permission'):format(src, name))
            return false, L('no_permission')
        end
        return handler(src, ...)
    end)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------
MySQL.ready(function()
    if Config.Database.autoInstall then
        DB.Install()
    end
    Heists.Load()
    Cooldowns.Load()
    Settings.Load()
    ready = true

    local count = 0
    for _ in pairs(Heists.list) do count = count + 1 end
    print(('[Heist Creator] loaded %d heist(s)'):format(count))
end)

---------------------------------------------------------------------------
-- Heist HUD
---------------------------------------------------------------------------
local function buildHud(src)
    local citizenid = Framework.GetIdentifier(src)
    if not citizenid then return false, L('not_loaded') end

    local xp = XP.Get(citizenid)
    local rank, nextXp, rankXp = Utils.GetRank(xp)

    local heists = {}
    for _, heist in pairs(Heists.list) do
        if heist.enabled then
            heists[#heists + 1] = Heists.Public(heist, citizenid, xp)
        end
    end
    table.sort(heists, function(a, b)
        if a.requiredXp ~= b.requiredXp then return a.requiredXp < b.requiredXp end
        return a.id < b.id
    end)

    local bonus = {}
    for size, value in pairs(Config.XP.partyBonus) do
        bonus[#bonus + 1] = { size = size, percent = math.floor(value * 100 + 0.5) }
    end
    table.sort(bonus, function(a, b) return a.size < b.size end)

    local party = Party.Get(src)
    local session = Sessions.byPlayer[src]

    return {
        player = { id = src, name = Framework.GetName(src), xp = xp, rank = rank, nextXp = nextXp, rankXp = rankXp },
        police = Framework.GetPoliceCount(),
        heists = heists,
        party = party and Party.Snapshot(party) or nil,
        invites = Party.GetInvites(src),
        bonus = bonus,
        genres = Settings.genres,
        tags = Settings.tags,
        maxParty = Config.Party.maxSize,
        activeHeist = session and session.heist.id or nil,
    }
end

register('getNpcs', function()
    return Settings.npcs
end)

register('getHud', function(src)
    return buildHud(src)
end)

register('party', function(src, action, target)
    if action == 'create' then
        local party, err = Party.Create(src)
        return party ~= nil, err or L('party_created')
    elseif action == 'invite' then
        return Party.Invite(src, target)
    elseif action == 'accept' then
        return Party.Accept(src, target)
    elseif action == 'decline' then
        return Party.Decline(src, target)
    elseif action == 'leave' then
        return Party.Leave(src)
    elseif action == 'kick' then
        return Party.Kick(src, target)
    elseif action == 'nearby' then
        return true, Party.Nearby(src)
    end
    return false, L('invalid_data')
end)

register('startHeist', function(src, heistId)
    return Sessions.Start(src, heistId)
end)

register('cancelHeist', function(src)
    return Sessions.Cancel(src)
end)

---------------------------------------------------------------------------
-- Heist progress
---------------------------------------------------------------------------
register('beginStage', function(src, index)
    return Sessions.BeginStage(src, tonumber(index))
end)

register('finishStage', function(src, index, success)
    return Sessions.FinishStage(src, tonumber(index), success)
end)

register('beginLoot', function(src, index)
    return Sessions.BeginLoot(src, tonumber(index))
end)

register('finishLoot', function(src, index, completed)
    return Sessions.FinishLoot(src, tonumber(index), completed)
end)

register('extract', function(src)
    return Sessions.Extract(src)
end)

register('claimGuards', function(src, indices)
    return Sessions.ClaimGuards(src, indices)
end)

RegisterNetEvent('heist_creator:server:guardsSpawned', function(list)
    Sessions.RegisterGuards(source, list)
end)

register('claimProps', function(src, indices)
    return Sessions.ClaimProps(src, indices)
end)

RegisterNetEvent('heist_creator:server:propsSpawned', function(list)
    Sessions.RegisterProps(source, list)
end)

---------------------------------------------------------------------------
-- Creator (admin only, checked on every request)
---------------------------------------------------------------------------
local function creatorMeta()
    local groups, available = {}, {}
    for i = 1, #Config.MinigameGroups do
        local group = Config.MinigameGroups[i]
        available[group.id] = not group.resource or GetResourceState(group.resource) == 'started'
        groups[i] = { id = group.id, label = group.label, resource = group.resource, available = available[group.id] }
    end

    local minigames = {}
    for id, minigame in pairs(Config.Minigames) do
        local group = available[minigame.group] ~= nil and minigame.group or 'basic'
        minigames[#minigames + 1] = {
            id = id,
            label = minigame.label or id,
            desc = minigame.desc or '',
            group = group,
            order = minigame.order or 0,
            available = not minigame.resource or GetResourceState(minigame.resource) == 'started',
        }
    end
    table.sort(minigames, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)

    return {
        items = Framework.GetItemList(),
        minigames = minigames,
        minigameGroups = groups,
        difficulties = Config.MinigameDifficulties,
        behaviors = Config.Guards.behaviors,
        models = Config.Guards.models,
        weapons = Config.Guards.weapons,
        limits = Config.Limits,
        maxParty = Config.Party.maxSize,
        defaultNpcModel = Config.Npc.defaultModel,
        doorsAvailable = Doors.Available(),
        genres = Settings.genres,
        tags = Settings.tags,
        propFavourites = Config.Props.favourites,
    }
end

register('admin:getData', function(src)
    return { heists = Heists.AdminList(), npcs = Settings.npcs, meta = creatorMeta(), doors = Doors.List(src) }
end, true)

register('admin:getDoors', function(src)
    return true, Doors.List(src)
end, true)

register('admin:save', function(src, input)
    local ok, result = Heists.Save(src, input)
    if not ok then return false, result end
    return true, { id = result, heists = Heists.AdminList() }
end, true)

register('admin:delete', function(_, id)
    local ok, err = Heists.Delete(tonumber(id))
    if not ok then return false, err end
    return true, { heists = Heists.AdminList() }
end, true)

register('admin:toggle', function(_, id, enabled)
    local ok, err = Heists.SetEnabled(tonumber(id), enabled == true)
    if not ok then return false, err end
    return true, { heists = Heists.AdminList() }
end, true)

register('admin:resetCooldown', function(_, id)
    id = tonumber(id)
    if not id or not Heists.list[id] then return false, L('heist_not_found') end
    Cooldowns.Clear(id)
    return true, L('cooldown_reset')
end, true)

register('admin:saveTaxonomy', function(_, genres, tags)
    local ok, err = Settings.SaveTaxonomy(genres, tags)
    if not ok then return false, err end
    return true, { genres = Settings.genres, tags = Settings.tags }
end, true)

register('admin:saveNpcs', function(_, npcs)
    local ok, err = Settings.SaveNpcs(npcs)
    if not ok then return false, err end
    return true, { npcs = Settings.npcs }
end, true)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
lib.addCommand(Config.Commands.create, {
    help = L('cmd_create'),
    restricted = Config.AdminGroups,
}, function(source)
    if source == 0 then return end
    TriggerClientEvent('heist_creator:client:openCreator', source)
end)

lib.addCommand(Config.Commands.setxp, {
    help = L('cmd_setxp'),
    restricted = Config.AdminGroups,
    params = {
        { name = 'target', type = 'playerId', help = L('cmd_param_player') },
        { name = 'amount', type = 'number', help = 'XP' },
    },
}, function(source, args)
    local citizenid = Framework.GetIdentifier(args.target)
    local message
    if not citizenid then
        message = L('party_invalid_target')
    else
        XP.Set(citizenid, args.amount)
        message = L('xp_set', Framework.GetName(args.target), XP.Get(citizenid))
    end
    if source == 0 then print(message) else notify(source, message, 'info') end
end)

lib.addCommand(Config.Commands.cancel, { help = L('cmd_cancel') }, function(source)
    if source == 0 then return end
    local ok, message = Sessions.Cancel(source)
    -- On success the player is informed by the "finish" event.
    if not ok then notify(source, message, 'error') end
end)

lib.addCommand(Config.Commands.accept, { help = L('cmd_accept') }, function(source)
    if source == 0 then return end
    local ok, message = Party.Accept(source)
    notify(source, message, ok and 'success' or 'error')
end)

lib.addCommand(Config.Commands.decline, { help = L('cmd_decline') }, function(source)
    if source == 0 then return end
    local ok, message = Party.Decline(source)
    notify(source, message, ok and 'info' or 'error')
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function playerGone(src)
    Party.PlayerDropped(src)
    -- Safety net: a session without a party entry (should never happen).
    local session = Sessions.byPlayer[src]
    if session then Sessions.RemoveMember(session, src, true) end
    lastRequest[src] = nil
end

AddEventHandler('playerDropped', function()
    playerGone(source)
end)

-- Qbox: the player went back to character selection.
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    playerGone(src)
    TriggerClientEvent('heist_creator:client:finish', src, 'left')
    TriggerClientEvent('heist_creator:client:partyUpdate', src, nil)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Running heists cannot survive a restart: end them cleanly (no cooldown is
    -- applied) and remove every guard that was spawned.
    Sessions.EndAll('restart')
end)
