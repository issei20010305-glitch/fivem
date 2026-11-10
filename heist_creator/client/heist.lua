-- Active heist on the client: interactions, guards, objectives.
-- The client never decides anything: it asks the server, which validates and
-- then pushes the new state to every party member.
local active = nil      -- { heist = table, state = table }
local myGuards = {}     -- peds spawned by this client
local GUARD_GROUP = GetHashKey('HEIST_CREATOR_GUARDS')

local function vec(coords)
    return vector3(coords.x, coords.y, coords.z)
end

---------------------------------------------------------------------------
-- Animations
---------------------------------------------------------------------------
local function playWorkAnim()
    local ped = cache.ped
    if IsPedInAnyVehicle(ped, false) then return end
    local dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@'
    if lib.requestAnimDict(dict, 3000) then
        TaskPlayAnim(ped, dict, 'machinic_loop_mechandplayer', 3.0, 3.0, -1, 1, 0.0, false, false, false)
        RemoveAnimDict(dict)
    end
end

local function stopWorkAnim()
    ClearPedTasks(cache.ped)
end

---------------------------------------------------------------------------
-- Interactions
---------------------------------------------------------------------------
local function doStage(index)
    if not active then return end
    local stage = active.heist.stages[index]
    if not stage then return end

    local ok, err = lib.callback.await('heist_creator:beginStage', false, index)
    if not ok then
        Notify(err, 'error')
        return
    end

    playWorkAnim()
    local success = RunMinigame(stage.minigame, stage.difficulty)
    stopWorkAnim()

    local done, message = lib.callback.await('heist_creator:finishStage', false, index, success)
    if not done then
        Notify(message or L('stage_failed'), 'error')
    end
end

local function doLoot(index)
    if not active then return end

    local ok, result = lib.callback.await('heist_creator:beginLoot', false, index)
    if not ok then
        Notify(result, 'error')
        return
    end

    local completed = lib.progressCircle({
        duration = (tonumber(result) or 8) * 1000,
        label = L('looting'),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@prop_human_bum_bin@idle_b', clip = 'idle_d' },
    })

    local done, rewards = lib.callback.await('heist_creator:finishLoot', false, index, completed == true)
    if not done then
        Notify(rewards, 'error')
        return
    end

    if type(rewards) ~= 'table' or #rewards == 0 then
        Notify(L('loot_nothing'), 'info')
        return
    end

    local parts, dropped = {}, false
    for i = 1, #rewards do
        parts[i] = ('%s x%d'):format(rewards[i].label, rewards[i].count)
        dropped = dropped or rewards[i].dropped
    end
    Notify(L('loot_received', table.concat(parts, '、')), 'success', 8000)
    if dropped then Notify(L('loot_dropped'), 'error', 8000) end
end

local function doExtract()
    if not active then return end
    local remaining = 0
    for i = 1, #active.state.looted do
        if not active.state.looted[i] then remaining = remaining + 1 end
    end

    if remaining > 0 then
        local answer = lib.alertDialog({
            header = L('extract_confirm_title'),
            content = L('extract_confirm_text', remaining),
            centered = true,
            cancel = true,
            labels = { confirm = L('extract_label'), cancel = L('word_back') },
        })
        if answer ~= 'confirm' then return end
    end

    local ok, err = lib.callback.await('heist_creator:extract', false)
    if not ok then Notify(err, 'error') end
end

---------------------------------------------------------------------------
-- Objectives / blips / interaction points, rebuilt from the server state
---------------------------------------------------------------------------
local function refresh()
    if not active then return end
    local heist, state = active.heist, active.state
    local blipStyles = Config.Guidance.blips
    local interactions, blips = {}, {}
    local text, step

    if state.phase == 'travel' then
        blips.start = true
        Guidance.SetBlip('start', heist.start, blipStyles.start, L('blip_start'))
        Guidance.SetPrimary('start', heist.start)
        text = L('obj_travel')

    elseif state.phase == 'stages' then
        local index = state.stage
        local stage = heist.stages[index]
        local id = ('stage:%d'):format(index)
        local label = stage.label ~= '' and stage.label or L('stage_default_label')

        blips[id] = true
        Guidance.SetBlip(id, stage.coords, blipStyles.stage, label)
        Guidance.SetPrimary(id, stage.coords)

        interactions[id] = true
        if not Interact.Exists(id) then
            Interact.Add(id, {
                coords = vec(stage.coords),
                type = stage.interaction,
                label = label,
                icon = 'fa-solid fa-laptop-code',
                onUse = function() doStage(index) end,
            })
        end

        text = stage.label ~= '' and stage.label or L('obj_stage')
        step = L('step_stage', index, #heist.stages)

    elseif state.phase == 'loot' or state.phase == 'extract' then
        local remaining = 0
        if state.phase == 'loot' then
            for i = 1, #heist.loots do
                if not state.looted[i] then
                    remaining = remaining + 1
                    local loot = heist.loots[i]
                    local id = ('loot:%d'):format(i)
                    local label = loot.label ~= '' and loot.label or L('loot_default_label')

                    blips[id] = true
                    Guidance.SetBlip(id, loot.coords, blipStyles.loot, label)
                    if remaining == 1 then Guidance.SetPrimary(id, loot.coords) end

                    interactions[id] = true
                    if not Interact.Exists(id) then
                        Interact.Add(id, {
                            coords = vec(loot.coords),
                            type = loot.interaction,
                            label = label,
                            icon = 'fa-solid fa-sack-dollar',
                            onUse = function() doLoot(i) end,
                        })
                    end
                end
            end
        end

        -- The heist is handed in at the NPC it was started from (see client/npc.lua).
        if state.npc then
            blips.finish = true
            Guidance.SetBlip('finish', state.npc, blipStyles.finish, L('blip_finish'))
            if remaining == 0 then Guidance.SetPrimary('finish', state.npc) end
        end

        if remaining > 0 then
            text = L('obj_loot')
            step = L('step_loot', #heist.loots - remaining, #heist.loots)
        else
            text = L('obj_extract')
        end
    end

    Guidance.SetArea(Config.Area.showOnMap and state.area or nil)
    Interact.Prune(interactions)
    Guidance.PruneBlips(blips)

    if text then
        Guidance.SetObjective({
            title = heist.name,
            text = text,
            step = step,
            timeLeft = state.timeLeft,
            members = state.members,
        })
    end
end

---------------------------------------------------------------------------
-- Guards
---------------------------------------------------------------------------
local function spawnGuard(guard)
    local model = GetHashKey(guard.model)
    if not IsModelInCdimage(model) or not IsModelAPed(model) then
        print(('[Heist Creator] invalid guard model "%s"'):format(guard.model))
        return nil
    end
    if not lib.requestModel(model, 10000) then return nil end

    local c = guard.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w or 0.0, true, true)
    SetModelAsNoLongerNeeded(model)
    if not ped or ped == 0 then return nil end

    SetEntityAsMissionEntity(ped, true, true)
    SetPedRelationshipGroupHash(ped, GUARD_GROUP)

    SetEntityMaxHealth(ped, 100 + guard.health)
    SetEntityHealth(ped, 100 + guard.health)
    SetPedArmour(ped, guard.armour)
    SetPedAccuracy(ped, guard.accuracy)
    SetPedSuffersCriticalHits(ped, Config.Guards.headshots)
    SetPedDropsWeaponsWhenDead(ped, Config.Guards.dropWeapons)

    local weapon = GetHashKey(guard.weapon)
    if weapon ~= GetHashKey('WEAPON_UNARMED') then
        GiveWeaponToPed(ped, weapon, 500, false, true)
        SetCurrentPedWeapon(ped, weapon, true)
    end

    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true) -- always fight
    SetPedCombatAttributes(ped, 5, true)  -- fight armed peds even when unarmed
    SetPedCombatAbility(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedSeeingRange(ped, 70.0)
    SetPedHearingRange(ped, 70.0)
    SetPedAlertness(ped, 3)
    SetPedAsEnemy(ped, true)
    SetPedKeepTask(ped, true)

    if guard.behavior == 'stationary' then
        SetPedCombatMovement(ped, 0)
        TaskGuardCurrentPosition(ped, 3.0, 3.0, true)
    elseif guard.behavior == 'defensive' then
        SetPedCombatMovement(ped, 1)
        TaskGuardCurrentPosition(ped, 10.0, 10.0, true)
    elseif guard.behavior == 'patrol' then
        SetPedCombatMovement(ped, 2)
        TaskWanderInArea(ped, c.x, c.y, c.z, 12.0, 2.0, 6.0)
    else
        SetPedCombatMovement(ped, 2)
        TaskCombatHatedTargetsAroundPed(ped, 60.0, 0)
    end

    return ped
end

-- Guards are requested when this client gets close. The server grants each
-- guard to exactly one client, so nothing is spawned twice.
CreateThread(function()
    while true do
        Wait(1500)
        if active and #active.heist.guards > 0 then
            local coords = GetEntityCoords(cache.ped)
            local wanted = {}
            for i = 1, #active.heist.guards do
                if not active.state.guards[i]
                    and #(coords - vec(active.heist.guards[i].coords)) <= Config.Guards.spawnDistance then
                    wanted[#wanted + 1] = i
                end
            end

            if #wanted > 0 then
                local granted = lib.callback.await('heist_creator:claimGuards', false, wanted)
                if active and type(granted) == 'table' and #granted > 0 then
                    local spawned = {}
                    for i = 1, #granted do
                        local index = granted[i]
                        active.state.guards[index] = true
                        local ped = spawnGuard(active.heist.guards[index])
                        if ped then
                            myGuards[#myGuards + 1] = ped
                            spawned[#spawned + 1] = { index = index, netId = NetworkGetNetworkIdFromEntity(ped) }
                        end
                    end
                    if #spawned > 0 then
                        TriggerServerEvent('heist_creator:server:guardsSpawned', spawned)
                    end
                end
            end
        end
    end
end)

local function deleteMyGuards()
    for i = 1, #myGuards do
        local ped = myGuards[i]
        if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
            DeleteEntity(ped)
        end
    end
    myGuards = {}
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function cleanup()
    active = nil
    CancelNuiMinigame()
    if lib.progressActive() then lib.cancelProgress() end
    if lib.skillCheckActive() then lib.cancelSkillCheck() end
    Interact.Clear()
    Guidance.Clear()
    deleteMyGuards()
end

function IsInHeist()
    return active ~= nil
end

---Whether the heist can be handed in at the NPC standing at these coordinates.
---@param x number
---@param y number
function CanFinishHeistAt(x, y)
    if not active then return false end
    local state = active.state
    if state.phase ~= 'loot' and state.phase ~= 'extract' then return false end
    local npc = state.npc
    return npc ~= nil and math.abs(npc.x - x) < 1.0 and math.abs(npc.y - y) < 1.0
end

function FinishHeist()
    if Interact.busy then return end
    Interact.busy = true
    local ok, err = pcall(doExtract)
    Interact.busy = false
    if not ok then print(('[Heist Creator] %s'):format(err)) end
end

RegisterNetEvent('heist_creator:client:start', function(heist, state)
    if type(heist) ~= 'table' or type(state) ~= 'table' then return end
    cleanup()
    active = { heist = heist, state = state }
    Notify(L('heist_started', heist.name), 'success')
    refresh()
end)

RegisterNetEvent('heist_creator:client:sync', function(state)
    if not active or type(state) ~= 'table' or state.heistId ~= active.heist.id then return end
    active.state = state
    refresh()
end)

RegisterNetEvent('heist_creator:client:finish', function(reason, result)
    if not active then return end
    local name = active.heist.name
    cleanup()

    if reason == 'completed' then
        if result and result.participated then
            local text = result.bonus > 0
                and L('heist_completed_bonus', name, result.xp, result.bonus)
                or L('heist_completed', name, result.xp)
            Notify(text, 'success', 10000)
        else
            Notify(L('heist_completed_absent', name), 'info', 10000)
        end
    elseif reason == 'cancelled' then
        Notify(L('heist_cancelled'), 'error')
    elseif reason == 'left_area' then
        Notify(L('heist_left_area'), 'error', 10000)
    elseif reason == 'timeout' then
        Notify(L('heist_timeout'), 'error')
    elseif reason == 'left' then
        Notify(L('heist_left'), 'info')
    elseif reason == 'restart' or reason == 'admin' then
        Notify(L('heist_aborted'), 'error')
    else
        Notify(L('heist_failed'), 'error')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Interact.Clear()
    Guidance.PruneBlips({})
    deleteMyGuards()
    lib.hideTextUI()
end)
