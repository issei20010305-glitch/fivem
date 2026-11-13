-- Active heists. The server owns the whole state machine:
--   travel -> stages -> loot -> extract -> (completed)
-- Clients only ever ask to perform an action; every request is validated here.
Sessions = {
    list = {},     -- [sessionId] = session
    byHeist = {},  -- [heistId] = session
    byPlayer = {}, -- [src] = session
}

local nextId = 0

local function notify(src, message, kind)
    TriggerClientEvent('heist_creator:client:notify', src, message, kind or 'info')
end

local function notifyAll(session, message, kind, except)
    for i = 1, #session.members do
        if session.members[i] ~= except then
            notify(session.members[i], message, kind)
        end
    end
end

local function toVector(coords)
    return vector3(coords.x, coords.y, coords.z)
end

---Server-side distance check, never trusts client coordinates.
local function isNear(src, coords, distance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - toVector(coords)) <= distance
end

local function lockExpired(lock)
    return not lock or os.time() - lock.at > Config.Security.lockTimeout
end

---------------------------------------------------------------------------
-- Heist area and police alert
---------------------------------------------------------------------------
---The area the crew has to stay in, or nil when there is none (anymore).
---It applies until every stage is cleared AND at least one point was looted.
---@return { x: number, y: number, z: number, radius: number }?
function Sessions.ActiveArea(session)
    local heist = session.heist
    if (heist.areaRadius or 0) <= 0 or not session.reached then return nil end
    local active = session.phase == 'stages' or (session.phase == 'loot' and session.lootCount == 0)
    if not active then return nil end
    local center = heist.areaCenter or heist.start
    return { x = center.x, y = center.y, z = center.z, radius = heist.areaRadius }
end

---Alerts the police once per heist, at the moment chosen in the creator.
---@param session table
---@param event 'arrival'|'stage_begin'|'stage_done'|'loot'
---@param src number player that caused it
---@param stage? number stage index for the stage events
local function policeAlert(session, event, src, stage)
    local heist = session.heist
    if session.alerted or not Config.PoliceAlert.enabled then return end
    if (heist.alertTrigger or 'arrival') ~= event then return end
    if stage and stage ~= (heist.alertStage or 1) then return end
    session.alerted = true

    local position = heist.alertCoords or heist.start
    local coords = vector3(position.x, position.y, position.z)
    local alert = {
        title = heist.alertTitle ~= nil and heist.alertTitle ~= '' and heist.alertTitle or L('police_default_title', heist.name),
        code = heist.alertCode ~= nil and heist.alertCode ~= '' and heist.alertCode or '10-90',
    }

    if Config.PoliceAlert.custom and Config.PoliceAlert.custom(coords, heist.name, alert) then return end

    local system = Config.PoliceAlert.system
    local dispatchRunning = GetResourceState('ps-dispatch') == 'started'
    if system == 'ps-dispatch' or (system == 'auto' and dispatchRunning) then
        -- ps-dispatch alerts are created on a client (it adds the street name).
        TriggerClientEvent('heist_creator:client:dispatch', src, {
            x = position.x, y = position.y, z = position.z,
            title = alert.title, code = alert.code, information = heist.name,
        })
        return
    end

    for _, officer in ipairs(Framework.GetPoliceSources()) do
        TriggerClientEvent('heist_creator:client:policeAlert', officer, coords, alert.title)
    end
end

---------------------------------------------------------------------------
-- State synchronisation
---------------------------------------------------------------------------
local function snapshot(session)
    local heist = session.heist
    local looted, guards = {}, {}
    for i = 1, #heist.loots do looted[i] = session.looted[i] == true end
    for i = 1, #heist.guards do guards[i] = session.guards[i] ~= nil end
    local props = {}
    for i = 1, #(heist.props or {}) do props[i] = session.props[i] ~= nil end

    local members = {}
    for i = 1, #session.members do
        members[i] = { id = session.members[i], name = Framework.GetName(session.members[i]) }
    end

    local timeLeft
    if session.deadline then
        timeLeft = math.max(0, session.deadline - os.time())
    end

    return {
        id = session.id,
        heistId = heist.id,
        phase = session.phase,
        stage = session.stage,
        looted = looted,
        guards = guards,
        props = props,
        members = members,
        leader = session.party.leader,
        npc = session.npc,
        area = Sessions.ActiveArea(session),
        timeLeft = timeLeft,
    }
end

---Sends the current state to every member of the session.
---@param session table
function Sessions.Sync(session)
    if not Sessions.list[session.id] then return end
    local state = snapshot(session)
    for i = 1, #session.members do
        TriggerClientEvent('heist_creator:client:sync', session.members[i], state)
    end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
---@param src number
---@param heistId number
---@return boolean ok, string? error
function Sessions.Start(src, heistId)
    heistId = tonumber(heistId)
    local heist = heistId and Heists.list[heistId]
    if not heist or not heist.enabled then return false, L('heist_not_found') end

    local citizenid = Framework.GetIdentifier(src)
    if not citizenid then return false, L('not_loaded') end

    local party = Party.Get(src)
    if not party then
        local err
        party, err = Party.Create(src)
        if not party then return false, err end
    end

    if party.leader ~= src then return false, L('party_not_leader') end
    if party.session then return false, L('already_in_heist') end
    if Sessions.byHeist[heistId] then return false, L('heist_in_progress') end
    local npc = Settings.NearestNpc(src, Config.Start.npcDistance)
    if not npc then return false, L('too_far_npc') end

    local size = #party.members
    if size < heist.minPlayers then return false, L('need_players', heist.minPlayers) end
    if size > heist.maxPlayers then return false, L('too_many_players', heist.maxPlayers) end

    local police = Framework.GetPoliceCount()
    if police < heist.minPolice then return false, L('need_police', heist.minPolice, police) end

    local globalLeft = Cooldowns.Remaining(heistId, DB.GLOBAL_OWNER)
    if globalLeft > 0 then return false, L('cooldown_global', Utils.FormatTime(globalLeft)) end

    local identifiers = {}
    for i = 1, size do
        local member = party.members[i]
        local memberCid = Framework.GetIdentifier(member)
        if not memberCid then return false, L('member_not_ready', Framework.GetName(member)) end
        if Sessions.byPlayer[member] then return false, L('already_in_heist') end

        if (member == src or Config.XP.requireAllMembers) and XP.Get(memberCid) < heist.requiredXp then
            return false, member == src and L('need_xp', heist.requiredXp)
                or L('member_need_xp', Framework.GetName(member), heist.requiredXp)
        end

        local left = Cooldowns.Remaining(heistId, memberCid)
        if left > 0 then
            return false, member == src and L('cooldown_player', Utils.FormatTime(left))
                or L('member_cooldown', Framework.GetName(member), Utils.FormatTime(left))
        end
        identifiers[member] = memberCid
    end

    nextId = nextId + 1
    local session = {
        id = nextId,
        heist = heist,
        npc = npc, -- the heist is handed in at the NPC it was started from
        party = party,
        members = {},
        identifiers = identifiers, -- [src] = citizenid, kept for cooldowns after a disconnect
        phase = 'travel',
        stage = 1,
        looted = {},
        lootLocks = {},
        stageLock = nil,
        guards = {},
        props = {},
        reached = false,
        alerted = false,
        lootCount = 0,
        outside = {},       -- [src] = true while a member is outside the heist area
        outsideSince = nil, -- when the fail countdown started
        startedAt = os.time(),
        deadline = nil,
    }
    for i = 1, size do
        session.members[i] = party.members[i]
        Sessions.byPlayer[party.members[i]] = session
    end

    Sessions.list[session.id] = session
    Sessions.byHeist[heistId] = session
    party.session = session

    -- The server-wide cooldown starts as soon as the heist is started.
    Cooldowns.Set(heistId, DB.GLOBAL_OWNER, heist.globalCooldown)

    local state = snapshot(session)
    for i = 1, size do
        TriggerClientEvent('heist_creator:client:start', session.members[i], heist, state)
    end
    Party.Broadcast(party)
    Utils.Debug(('session %s started (heist %s, %s players)'):format(session.id, heistId, size))
    return true
end

---------------------------------------------------------------------------
-- End / cleanup
---------------------------------------------------------------------------
local function deleteGuards(session)
    for index, guard in pairs(session.guards) do
        if guard.netId then
            local entity = NetworkGetEntityFromNetworkId(guard.netId)
            local config = session.heist.guards[index]
            -- Only ever delete an entity that really is the configured guard ped.
            if entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 1
                and not IsPedAPlayer(entity) and config
                and (GetEntityModel(entity) & 0xFFFFFFFF) == (GetHashKey(config.model) & 0xFFFFFFFF) then
                DeleteEntity(entity)
            end
        end
    end
    session.guards = {}
end

---Removes every prop the heist spawned. Runs whenever a session ends.
local function deleteProps(session)
    for index, prop in pairs(session.props) do
        if prop.netId then
            local entity = NetworkGetEntityFromNetworkId(prop.netId)
            local config = session.heist.props[index]
            -- Only ever delete an entity that really is the configured prop.
            if entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 3 and config
                and (GetEntityModel(entity) & 0xFFFFFFFF) == (GetHashKey(config.model) & 0xFFFFFFFF) then
                DeleteEntity(entity)
            end
        end
    end
    session.props = {}
end

---Personal cooldowns start when the heist ends. (The server-wide cooldown
---already started with the heist, see Sessions.Start.)
local function applyCooldowns(session, reason)
    if reason == 'restart' or reason == 'admin' then return end
    if reason ~= 'completed' and not Config.Cooldowns.applyOnFail then return end

    local heist = session.heist
    for _, citizenid in pairs(session.identifiers) do
        Cooldowns.Set(heist.id, citizenid, heist.playerCooldown)
    end
end

---Ends a session for everybody.
---@param session table
---@param reason 'completed'|'cancelled'|'timeout'|'abandoned'|'left_area'|'restart'|'admin'
---@param results? table<number, table> per-player result (completed only)
function Sessions.End(session, reason, results)
    if not Sessions.list[session.id] then return end
    Sessions.list[session.id] = nil
    Sessions.byHeist[session.heist.id] = nil
    session.phase = 'ended'

    applyCooldowns(session, reason)
    deleteGuards(session)
    deleteProps(session)
    Doors.Release(session, reason == 'restart')

    for i = 1, #session.members do
        local member = session.members[i]
        Sessions.byPlayer[member] = nil
        TriggerClientEvent('heist_creator:client:finish', member, reason, results and results[member] or nil)
    end

    session.party.session = nil
    if Party.list[session.party.id] then
        Party.Broadcast(session.party)
    end
    Utils.Debug(('session %s ended (%s)'):format(session.id, reason))
end

---Removes one player from a running session (left the party, disconnected).
---@param session table
---@param src number
---@param silent? boolean
function Sessions.RemoveMember(session, src, silent)
    if Sessions.byPlayer[src] ~= session then return end
    Sessions.byPlayer[src] = nil
    Utils.RemoveValue(session.members, src)

    if session.stageLock and session.stageLock.src == src then session.stageLock = nil end
    for index, lock in pairs(session.lootLocks) do
        if lock.src == src then session.lootLocks[index] = nil end
    end

    -- A player that leaves the heist gets the personal cooldown right away.
    local citizenid = session.identifiers[src]
    if citizenid then
        session.identifiers[src] = nil
        if Config.Cooldowns.applyOnFail then
            Cooldowns.Set(session.heist.id, citizenid, session.heist.playerCooldown)
        end
    end
    session.outside[src] = nil

    if not silent then
        TriggerClientEvent('heist_creator:client:finish', src, 'left')
    end

    if #session.members == 0 then
        Sessions.End(session, 'abandoned')
    end
end

---------------------------------------------------------------------------
-- Phase transitions
---------------------------------------------------------------------------
local function phaseAfterStages(heist)
    return #heist.loots > 0 and 'loot' or 'extract'
end

local function arrive(session, src)
    local heist = session.heist
    session.reached = true
    session.phase = #heist.stages > 0 and 'stages' or phaseAfterStages(heist)
    if heist.timeLimit > 0 then
        session.deadline = os.time() + heist.timeLimit * 60
    end
    Doors.Prepare(session)
    policeAlert(session, 'arrival', src)

    Sessions.Sync(session)
end

local function complete(session, src)
    local heist = session.heist
    session.phase = 'completing' -- blocks every further request immediately

    local finish = session.npc
    local participants = {}
    for i = 1, #session.members do
        local member = session.members[i]
        if member == src or Config.XP.participationDistance <= 0
            or isNear(member, finish, Config.XP.participationDistance) then
            participants[#participants + 1] = member
        end
    end

    local bonus = Utils.PartyBonus(#participants)
    local xpGain = math.floor(heist.xpReward * (1.0 + bonus) + 0.5)
    local results = {}

    for i = 1, #participants do
        local member = participants[i]
        local citizenid = session.identifiers[member]
        if citizenid then
            local total = XP.Add(citizenid, xpGain, 1)
            results[member] = {
                participated = true,
                xp = xpGain,
                bonus = math.floor(bonus * 100 + 0.5),
                total = total,
                crew = #participants,
            }
        end
    end
    for i = 1, #session.members do
        local member = session.members[i]
        results[member] = results[member] or { participated = false }
    end

    Sessions.End(session, 'completed', results)
end

---------------------------------------------------------------------------
-- Player requests (called from server/main.lua callbacks)
---------------------------------------------------------------------------
---@return boolean ok, string? error
function Sessions.BeginStage(src, index)
    local session = Sessions.byPlayer[src]
    if not session or session.phase ~= 'stages' then return false, L('invalid_state') end
    if index ~= session.stage then return false, L('invalid_state') end

    local stage = session.heist.stages[index]
    if not isNear(src, stage.coords, Config.Security.interactDistance) then return false, L('too_far') end
    if not lockExpired(session.stageLock) and session.stageLock.src ~= src then
        return false, L('stage_in_use')
    end
    if stage.item ~= '' and Framework.GetItemCount(src, stage.item) < stage.itemCount then
        return false, L('need_item', Framework.ItemLabel(stage.item), stage.itemCount)
    end

    session.stageLock = { src = src, at = os.time(), timer = GetGameTimer() }
    policeAlert(session, 'stage_begin', src, index)
    return true
end

---@return boolean ok, string? error
function Sessions.FinishStage(src, index, success)
    local session = Sessions.byPlayer[src]
    if not session or session.phase ~= 'stages' or index ~= session.stage then
        return false, L('invalid_state')
    end

    local lock = session.stageLock
    if not lock or lock.src ~= src then return false, L('invalid_state') end
    session.stageLock = nil

    local heist = session.heist
    local stage = heist.stages[index]
    local name = Framework.GetName(src)

    if success ~= true then
        notifyAll(session, L('stage_failed_by', name), 'error', src)
        return false, L('stage_failed')
    end

    if GetGameTimer() - lock.timer < Config.Security.minStageSeconds * 1000 then
        return false, L('invalid_state')
    end
    if not isNear(src, stage.coords, Config.Security.interactDistance) then return false, L('too_far') end

    -- Awoken Minigames can confirm on the server that the player really won.
    local minigame = Config.Minigames[stage.minigame]
    if minigame and minigame.awoken and Config.Awoken.serverVerify
        and GetResourceState('awoken_minigames') == 'started' then
        local ok, verified = pcall(function()
            return exports.awoken_minigames:ConsumeResult(src, minigame.awoken)
        end)
        if ok and verified ~= true then
            print(('[Heist Creator] player %s reported a win for "%s" that awoken_minigames did not confirm')
                :format(src, minigame.awoken))
            return false, L('stage_unverified')
        end
    end

    if stage.item ~= '' then
        if Framework.GetItemCount(src, stage.item) < stage.itemCount then
            return false, L('need_item', Framework.ItemLabel(stage.item), stage.itemCount)
        end
        if stage.consume and not Framework.RemoveItem(src, stage.item, stage.itemCount) then
            return false, L('need_item', Framework.ItemLabel(stage.item), stage.itemCount)
        end
    end

    session.stage = index + 1
    if session.stage > #heist.stages then
        session.phase = phaseAfterStages(heist)
    end

    policeAlert(session, 'stage_done', src, index)
    notifyAll(session, L('stage_done_by', name, index, #heist.stages), 'success')
    if Doors.Unlock(session, stage.doors) then
        notifyAll(session, L('doors_unlocked'), 'info')
    end
    Sessions.Sync(session)
    return true
end

---@return boolean ok, string|number result error or loot duration in seconds
function Sessions.BeginLoot(src, index)
    local session = Sessions.byPlayer[src]
    if not session or session.phase ~= 'loot' then return false, L('invalid_state') end

    local loot = session.heist.loots[index]
    if not loot then return false, L('invalid_state') end
    if session.looted[index] then return false, L('loot_empty') end
    if not isNear(src, loot.coords, Config.Security.interactDistance) then return false, L('too_far') end

    local lock = session.lootLocks[index]
    if not lockExpired(lock) and lock.src ~= src then return false, L('loot_in_use') end

    -- One loot point per player at a time.
    for other, otherLock in pairs(session.lootLocks) do
        if otherLock.src == src then session.lootLocks[other] = nil end
    end

    session.lootLocks[index] = { src = src, at = os.time(), timer = GetGameTimer() }
    return true, loot.duration
end

---@return boolean ok, string|table result error or list of received rewards
function Sessions.FinishLoot(src, index, completed)
    local session = Sessions.byPlayer[src]
    if not session or session.phase ~= 'loot' then return false, L('invalid_state') end

    local heist = session.heist
    local loot = heist.loots[index]
    local lock = session.lootLocks[index]
    if not loot or not lock or lock.src ~= src then return false, L('invalid_state') end
    session.lootLocks[index] = nil

    if completed ~= true then return false, L('loot_cancelled') end
    if session.looted[index] then return false, L('loot_empty') end
    if GetGameTimer() - lock.timer < (loot.duration * 1000) - 750 then return false, L('invalid_state') end
    if not isNear(src, loot.coords, Config.Security.interactDistance) then return false, L('too_far') end

    -- Mark as looted BEFORE handing out anything: a second request can never pay out again.
    session.looted[index] = true
    local hadArea = Sessions.ActiveArea(session) ~= nil
    session.lootCount = session.lootCount + 1
    policeAlert(session, 'loot', src)
    if hadArea then
        session.outside, session.outsideSince = {}, nil
        notifyAll(session, L('area_released'), 'info')
    end

    local received = {}
    for i = 1, #loot.rewards do
        local reward = loot.rewards[i]
        if reward.guaranteed or math.random() * 100 < reward.chance then
            local amount = math.random(reward.min, reward.max)
            local given, dropped = Framework.GiveItem(src, reward.item, amount)
            if given then
                received[#received + 1] = {
                    label = Framework.ItemLabel(reward.item),
                    count = amount,
                    dropped = dropped,
                }
            end
        end
    end

    local remaining = 0
    for i = 1, #heist.loots do
        if not session.looted[i] then remaining = remaining + 1 end
    end
    if remaining == 0 then session.phase = 'extract' end

    notifyAll(session, L('loot_done_by', Framework.GetName(src), #heist.loots - remaining, #heist.loots), 'info', src)
    Sessions.Sync(session)
    return true, received
end

---@return boolean ok, string? error
function Sessions.Extract(src)
    local session = Sessions.byPlayer[src]
    if not session or (session.phase ~= 'loot' and session.phase ~= 'extract') then
        return false, L('invalid_state')
    end
    if not isNear(src, session.npc, Config.Security.interactDistance + 4.0) then
        return false, L('too_far')
    end
    complete(session, src)
    return true
end

---Guards are spawned by the first crew member that gets close. The server hands
---out each guard index exactly once so they can never be spawned twice.
---@param indices number[]
---@return number[] granted
function Sessions.ClaimGuards(src, indices)
    local granted = {}
    local session = Sessions.byPlayer[src]
    if not session or type(indices) ~= 'table' then return granted end

    local guards = session.heist.guards
    for i = 1, math.min(#indices, #guards) do
        local index = tonumber(indices[i])
        if index and guards[index] and not session.guards[index] then
            session.guards[index] = { owner = src }
            granted[#granted + 1] = index
        end
    end
    if #granted > 0 then Sessions.Sync(session) end
    return granted
end

---@param list { index: number, netId: number }[]
function Sessions.RegisterGuards(src, list)
    local session = Sessions.byPlayer[src]
    if not session or type(list) ~= 'table' then return end
    for i = 1, math.min(#list, #session.heist.guards) do
        local entry = list[i]
        local index = type(entry) == 'table' and tonumber(entry.index)
        local netId = type(entry) == 'table' and tonumber(entry.netId)
        local guard = index and session.guards[index]
        if guard and netId and guard.owner == src and not guard.netId then
            guard.netId = netId
        end
    end
end

---Props work like guards: each one is handed to exactly one client to spawn.
---@param indices number[]
---@return number[] granted
function Sessions.ClaimProps(src, indices)
    local granted = {}
    local session = Sessions.byPlayer[src]
    if not session or type(indices) ~= 'table' then return granted end

    local props = session.heist.props or {}
    for i = 1, math.min(#indices, #props) do
        local index = tonumber(indices[i])
        if index and props[index] and not session.props[index] then
            session.props[index] = { owner = src }
            granted[#granted + 1] = index
        end
    end
    if #granted > 0 then Sessions.Sync(session) end
    return granted
end

---@param list { index: number, netId: number }[]
function Sessions.RegisterProps(src, list)
    local session = Sessions.byPlayer[src]
    if not session or type(list) ~= 'table' then return end
    for i = 1, math.min(#list, #(session.heist.props or {})) do
        local entry = list[i]
        local index = type(entry) == 'table' and tonumber(entry.index)
        local netId = type(entry) == 'table' and tonumber(entry.netId)
        local prop = index and session.props[index]
        if prop and netId and prop.owner == src and not prop.netId then
            prop.netId = netId
        end
    end
end

---Leader cancels the heist, a member leaves it.
---@return boolean ok, string message
function Sessions.Cancel(src)
    local session = Sessions.byPlayer[src]
    if not session then return false, L('not_in_heist') end
    if session.party.leader == src then
        Sessions.End(session, 'cancelled')
        return true, L('heist_cancelled')
    end
    Party.Leave(src)
    return true, L('party_you_left')
end

---Ends every running session (resource stop).
function Sessions.EndAll(reason)
    for _, session in pairs(Sessions.list) do
        Sessions.End(session, reason)
    end
end

---Ends the heist when the crew left the heist area (see Config.Area).
local function checkArea(session, now)
    local area = Sessions.ActiveArea(session)
    if not area then return end

    local outsideCount = 0
    for i = 1, #session.members do
        local member = session.members[i]
        local outside = not isNear(member, area, area.radius)
        if outside then outsideCount = outsideCount + 1 end
        if outside ~= (session.outside[member] == true) then
            session.outside[member] = outside or nil
            if outside and Config.Area.mode ~= 'any' and outsideCount < #session.members then
                notify(member, L('area_warning_member'), 'error')
            end
        end
    end

    local failing = Config.Area.mode == 'any' and outsideCount > 0 or outsideCount == #session.members
    if not failing then
        if session.outsideSince then
            session.outsideSince = nil
            notifyAll(session, L('area_back'), 'success')
        end
        return
    end

    if not session.outsideSince then
        session.outsideSince = now
        notifyAll(session, L('area_warning', Config.Area.graceSeconds), 'error')
    end
    if now - session.outsideSince >= Config.Area.graceSeconds then
        Sessions.End(session, 'left_area')
    end
end

---------------------------------------------------------------------------
-- Tick: arrival at the starting point, time limits, heist area
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for _, session in pairs(Sessions.list) do
            if session.phase == 'travel' then
                local timeout = Config.Start.travelTimeout
                if timeout > 0 and now - session.startedAt > timeout * 60 then
                    Sessions.End(session, 'timeout')
                else
                    local heist = session.heist
                    for i = 1, #session.members do
                        if isNear(session.members[i], heist.start, heist.startRadius) then
                            arrive(session, session.members[i])
                            break
                        end
                    end
                end
            elseif session.deadline and now >= session.deadline then
                Sessions.End(session, 'timeout')
            else
                checkArea(session, now)
            end
        end
    end
end)
