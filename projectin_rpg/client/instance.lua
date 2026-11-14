--[[ クライアント: インスタンス内の処理 ]]
Run = nil
local RELGROUP = GetHashKey('RPG_ENEMY')
local configured = {}

local function nativeFromRpg(hp) return 100 + Run.buffer + math.floor(hp * Run.scale) end
local function rpgFromNative(h) return math.max(0, math.floor((h - 100 - Run.buffer) / Run.scale + 0.5)) end
function RPGClient.MyHp()
    if not Run then return 0, 0 end
    return rpgFromNative(GetEntityHealth(PlayerPedId())), Run.maxHp
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function draw3dText(x, y, z, text, scale)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end
    SetTextScale(0.0, scale or 0.32)
    SetTextFont(0)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 230)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function groundZ(x, y, z)
    for _, off in ipairs({ 3.0, 10.0, 30.0, 80.0 }) do
        local ok, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + off, false)
        if ok then return gz end
    end
    return z
end

local function teleport(pos, snap)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    SetEntityCoords(ped, pos.x, pos.y, pos.z, false, false, false, false)
    FreezeEntityPosition(ped, true)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 4000 do
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)
        Wait(50)
    end
    local z = pos.z
    if snap then z = groundZ(pos.x, pos.y, pos.z) end
    SetEntityCoords(ped, pos.x, pos.y, z, false, false, false, false)
    SetEntityHeading(ped, pos.h or 0.0)
    FreezeEntityPosition(ped, false)
end

---------------------------------------------------------------------------
-- 入場
---------------------------------------------------------------------------
RegisterNetEvent('projectin_rpg:client:enterRun', function(data)
    if NUI.open then NUI.Close() end
    local ped = PlayerPedId()
    Run = {
        id = data.runId, name = data.name, type = data.type, test = data.testMode, role = data.role, roleLabel = data.roleLabel,
        canAttack = data.canAttack, maxHp = data.maxHp, buffer = data.downedBuffer, scale = data.nativeScale,
        boundary = data.boundary, start = data.start, skills = data.skills, maxMp = data.maxMp,
        downed = false, drops = {}, aoes = {}, enemies = {}, fx = {}, objective = {}, party = {}, me = {},
        prevMaxHealth = GetEntityMaxHealth(ped), iplsAdded = {}, outsideSince = nil, target = nil,
    }
    RPGClient.inRun = true
    TriggerEvent('projectin_rpg:client:refreshBlips')
    DoScreenFadeOut(600)
    while not IsScreenFadedOut() do Wait(10) end
    for _, ipl in ipairs(data.ipls or {}) do
        if not IsIplActive(ipl) then RequestIpl(ipl) Run.iplsAdded[#Run.iplsAdded + 1] = ipl end
    end
    teleport(data.start, true)
    ped = PlayerPedId()
    local nmax = nativeFromRpg(Run.maxHp)
    SetEntityMaxHealth(ped, nmax)
    SetPedMaxHealth(ped, nmax)
    SetEntityHealth(ped, nmax)
    SetPedArmour(ped, 0)
    NetworkSetFriendlyFireOption(false)
    SetCanAttackFriendly(ped, false, false)
    AddRelationshipGroup('RPG_ENEMY')
    SetRelationshipBetweenGroups(5, RELGROUP, GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), RELGROUP)
    Wait(300)
    DoScreenFadeIn(800)
    NUI.Send('hud', {
        show = true, name = data.name, type = data.type, test = data.testMode, role = data.role, roleLabel = data.roleLabel,
        skills = data.skills, maxMp = data.maxMp, timeLimit = data.timeLimit,
    })
    PlaySoundFrontend(-1, 'Mission_Pass_Notify', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false)
end)

---------------------------------------------------------------------------
-- 退出 / 後片付け
---------------------------------------------------------------------------
local function resetPlayerState(health, armour)
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    if IsEntityDead(ped) then
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
    end
    ClearPedTasksImmediately(ped)
    local maxH = (Run and Run.prevMaxHealth and Run.prevMaxHealth > 100) and Run.prevMaxHealth or 200
    SetEntityMaxHealth(ped, maxH)
    SetPedMaxHealth(ped, maxH)
    local h = math.floor(tonumber(health) or maxH)
    if h < 101 or h > maxH then h = maxH end
    SetEntityHealth(ped, h)
    SetPedArmour(ped, math.floor(tonumber(armour) or 0))
    NetworkSetFriendlyFireOption(true)
    SetCanAttackFriendly(ped, true, false)
    if Run then
        for _, ipl in ipairs(Run.iplsAdded) do RemoveIpl(ipl) end
    end
end

local function finishCleanup()
    Run = nil
    configured = {}
    RPGClient.inRun = false
    NUI.Send('hud', { show = false })
    NUI.Send('downed', { show = false })
    NUI.Send('boundary', { show = false })
    TriggerEvent('projectin_rpg:client:refreshBlips')
end

RegisterNetEvent('projectin_rpg:client:exitRun', function(data)
    DoScreenFadeOut(500)
    local t = GetGameTimer()
    while not IsScreenFadedOut() and GetGameTimer() - t < 1500 do Wait(10) end
    resetPlayerState(data.health, data.armour)
    if data.pos then teleport(data.pos, true) end
    finishCleanup()
    if NUI.open then NUI.Close() end
    Wait(300)
    DoScreenFadeIn(800)
    if data.reason == 'leave' then NUI.Toast('ダンジョンから離脱しました', 'info')
    elseif data.reason == 'admin' then NUI.Toast('管理者によりインスタンスが終了されました', 'warning') end
end)

RegisterNetEvent('projectin_rpg:client:forceCleanupNet', function()
    TriggerEvent('projectin_rpg:client:forceCleanup')
end)

AddEventHandler('projectin_rpg:client:forceCleanup', function()
    if not Run then return end
    resetPlayerState()
    finishCleanup()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Run then return end
    -- サーバー側で座標・バケット・インベントリは復元される
    resetPlayerState()
    DoScreenFadeIn(0)
end)

---------------------------------------------------------------------------
-- HP 関連 (サーバーからの指示)
---------------------------------------------------------------------------
RegisterNetEvent('projectin_rpg:client:heal', function(amount)
    if not Run or Run.downed then return end
    local ped = PlayerPedId()
    local nmax = nativeFromRpg(Run.maxHp)
    SetEntityHealth(ped, math.min(nmax, GetEntityHealth(ped) + math.floor(amount * Run.scale)))
    Run.fx[#Run.fx + 1] = { ped = ped, color = { 80, 255, 140 }, untilT = GetGameTimer() + 1200 }
end)

RegisterNetEvent('projectin_rpg:client:damage', function(amount)
    if not Run or Run.downed then return end
    local ped = PlayerPedId()
    local h = GetEntityHealth(ped) - math.floor(amount * Run.scale)
    SetEntityHealth(ped, math.max(100 + Run.buffer, h))
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.25)
end)

RegisterNetEvent('projectin_rpg:client:revive', function(hp)
    if not Run then return end
    local ped = PlayerPedId()
    Run.downed = false
    SetEntityInvincible(ped, false)
    ClearPedTasks(ped)
    SetEntityHealth(ped, nativeFromRpg(hp))
    NUI.Send('downed', { show = false })
    Run.fx[#Run.fx + 1] = { ped = ped, color = { 255, 230, 120 }, untilT = GetGameTimer() + 1800 }
end)

RegisterNetEvent('projectin_rpg:client:teleportStart', function()
    if not Run then return end
    NUI.Toast('エリア外に出たため開始地点へ戻されました', 'warning')
end)

local function goDowned()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
        if Config.Medical.reviveClientEvent then TriggerEvent(Config.Medical.reviveClientEvent) end
    end
    Run.downed = true
    SetEntityHealth(ped, 100 + Run.buffer + 1)
    SetEntityInvincible(ped, true)
    lib.requestAnimDict('dead')
    TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, -8.0, -1, 1, 0, false, false, false)
    TriggerServerEvent('projectin_rpg:server:downed')
    NUI.Send('downed', { show = true })
end

---------------------------------------------------------------------------
-- サーバーからの同期
---------------------------------------------------------------------------
RegisterNetEvent('projectin_rpg:client:party', function(data)
    if not Run then return end
    Run.party = data.members
    Run.me = data.me
    NUI.Send('party', data)
end)
RegisterNetEvent('projectin_rpg:client:objective', function(data)
    if not Run then return end
    Run.objective = data
    NUI.Send('objective', data)
end)
RegisterNetEvent('projectin_rpg:client:enemies', function(list)
    if not Run then return end
    local map = {}
    for _, e in ipairs(list) do map[e.netId] = e end
    Run.enemies = map
end)
RegisterNetEvent('projectin_rpg:client:banner', function(data) NUI.Send('banner', data) end)
RegisterNetEvent('projectin_rpg:client:memberDowned', function(data)
    NUI.Toast(('%s が戦闘不能になった！'):format(data.name), 'error')
end)
RegisterNetEvent('projectin_rpg:client:dropAdded', function(d)
    if not Run then return end
    d.z = groundZ(d.x, d.y, d.z) + 0.3
    Run.drops[d.id] = d
end)
RegisterNetEvent('projectin_rpg:client:dropRemoved', function(id)
    if Run then Run.drops[id] = nil end
end)
RegisterNetEvent('projectin_rpg:client:dropsClear', function()
    if Run then Run.drops = {} end
end)
RegisterNetEvent('projectin_rpg:client:aoe', function(a)
    if not Run then return end
    a.z = groundZ(a.x, a.y, a.z)
    a.startT = GetGameTimer()
    a.endT = a.startT + math.floor(a.delay * 1000)
    Run.aoes[a.id] = a
    PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', false)
end)
RegisterNetEvent('projectin_rpg:client:aoeBoom', function(data)
    if not Run then return end
    local a = Run.aoes[data.id]
    Run.aoes[data.id] = nil
    if a then
        lib.requestNamedPtfxAsset('core')
        UseParticleFxAsset('core')
        StartParticleFxNonLoopedAtCoord('exp_grd_grenade_smoke', a.x, a.y, a.z, 0.0, 0.0, 0.0, a.radius / 3.0, false, false, false)
        PlaySoundFromCoord(-1, 'Explosion_Countdown', a.x, a.y, a.z, 'GTAO_FM_Events_Soundset', false, 0, false)
        if #(GetEntityCoords(PlayerPedId()) - vector3(a.x, a.y, a.z)) < a.radius + 8.0 then ShakeGameplayCam('MEDIUM_EXPLOSION_SHAKE', 0.3) end
    end
end)
RegisterNetEvent('projectin_rpg:client:propDestroyed', function(p)
    lib.requestNamedPtfxAsset('core')
    UseParticleFxAsset('core')
    StartParticleFxNonLoopedAtCoord('ent_dst_elec_fire_sp', p.x, p.y, p.z + 0.5, 0.0, 0.0, 0.0, 1.5, false, false, false)
    PlaySoundFrontend(-1, 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', false)
end)
RegisterNetEvent('projectin_rpg:client:skillFx', function(d)
    if not Run then return end
    local colors = { heal = { 80, 255, 140 }, buff = { 255, 120, 60 }, areaHeal = { 120, 255, 200 }, revive = { 255, 230, 120 } }
    local target = d.to or d.from
    local p = GetPlayerFromServerId(target)
    if p ~= -1 then
        Run.fx[#Run.fx + 1] = { ped = GetPlayerPed(p), color = colors[d.skill] or { 200, 200, 255 }, untilT = GetGameTimer() + 1200,
            radius = d.skill == 'areaHeal' and Config.Mage.skills.areaHeal.range or nil }
    end
end)
RegisterNetEvent('projectin_rpg:client:results', function(data)
    if not Run then return end
    NUI.Send('drops', {})
    NUI.Open('results', data)
end)

RegisterNUICallback('leaveRun', function(_, cb)
    NUI.Close()
    lib.callback.await('projectin_rpg:leaveRun', false)
    cb({})
end)

---------------------------------------------------------------------------
-- 敵 (所有クライアントがAI設定を行う)
---------------------------------------------------------------------------
local function configureEnemy(ent, st)
    SetEntityMaxHealth(ent, 5000)
    SetEntityHealth(ent, 5000)
    SetPedRelationshipGroupHash(ent, RELGROUP)
    SetPedAccuracy(ent, st.accuracy or 30)
    SetPedCombatAttributes(ent, 46, true)
    SetPedCombatAttributes(ent, 5, true)
    SetPedCombatAttributes(ent, 0, true)
    SetPedCombatAbility(ent, 2)
    SetPedCombatMovement(ent, 2)
    SetPedCombatRange(ent, 1)
    SetPedFleeAttributes(ent, 0, false)
    SetPedDropsWeaponsWhenDead(ent, false)
    SetPedSuffersCriticalHits(ent, false)
    SetPedConfigFlag(ent, 281, true)
    SetPedSeeingRange(ent, 120.0)
    SetPedHearingRange(ent, 120.0)
    SetPedKeepTask(ent, true)
    if st.boss then SetPedCanRagdoll(ent, false) end
    local c = GetEntityCoords(ent)
    local gz = groundZ(c.x, c.y, c.z)
    if math.abs(c.z - gz) > 1.2 then SetEntityCoordsNoOffset(ent, c.x, c.y, gz, false, false, false) end
    TaskCombatHatedTargetsAroundPed(ent, 120.0, 0)
end

CreateThread(function()
    while true do
        if Run then
            for netId in pairs(Run.enemies) do
                if NetworkDoesNetworkIdExist(netId) then
                    local ent = NetworkGetEntityFromNetworkId(netId)
                    if DoesEntityExist(ent) and NetworkGetEntityOwner(ent) == PlayerId() then
                        local st = Entity(ent).state.rpgEnemy
                        if st then
                            if Entity(ent).state.rpgDead then
                                if not IsEntityDead(ent) then SetEntityHealth(ent, 0) end
                            else
                                if configured[ent] ~= st.accuracy then
                                    configureEnemy(ent, st)
                                    configured[ent] = st.accuracy
                                end
                                if GetEntityHealth(ent) < 2500 then SetEntityHealth(ent, 5000) end
                                if not IsPedInCombat(ent, 0) then TaskCombatHatedTargetsAroundPed(ent, 120.0, 0) end
                            end
                        end
                    end
                end
            end
            -- 死亡した敵(リストから外れたもの)の後始末
            for ent in pairs(configured) do
                if not DoesEntityExist(ent) then configured[ent] = nil
                elseif Entity(ent).state.rpgDead and NetworkGetEntityOwner(ent) == PlayerId() and not IsEntityDead(ent) then
                    SetEntityHealth(ent, 0)
                end
            end
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

---------------------------------------------------------------------------
-- 毎フレーム処理
---------------------------------------------------------------------------
local interacting = nil

local function rarityColor(r)
    if r == 'legendary' then return 255, 150, 30 end
    if r == 'epic' then return 190, 90, 255 end
    if r == 'rare' then return 60, 150, 255 end
    if r == 'uncommon' then return 90, 230, 110 end
    return 230, 230, 230
end

CreateThread(function()
    while true do
        if not Run then
            Wait(500)
        else
            Wait(0)
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local gt = GetGameTimer()

            -- ダウン判定
            if not Run.downed and (IsEntityDead(ped) or GetEntityHealth(ped) <= 100 + Run.buffer) then
                goDowned()
            end
            if Run.downed then
                DisableAllControlActions(0)
                EnableControlAction(0, 1, true) EnableControlAction(0, 2, true) -- カメラ
                EnableControlAction(0, 245, true) EnableControlAction(0, 249, true) -- チャット/PTT
                if not IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3) and HasAnimDictLoaded('dead') then
                    TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, -8.0, -1, 1, 0, false, false, false)
                end
            end

            -- 魔導士は攻撃不可
            if not Run.canAttack then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)  -- 攻撃
                DisableControlAction(0, 25, true)  -- 照準
                DisableControlAction(0, 140, true) DisableControlAction(0, 141, true) DisableControlAction(0, 142, true) -- 近接
                DisableControlAction(0, 257, true) DisableControlAction(0, 263, true) DisableControlAction(0, 264, true)
            end

            -- 境界
            local b = Run.boundary
            local d2 = #(vector2(pc.x, pc.y) - vector2(b.center.x, b.center.y))
            if d2 > b.radius - 12.0 then
                DrawMarker(1, b.center.x, b.center.y, b.center.z - b.height / 2, 0, 0, 0, 0, 0, 0, b.radius * 2.0, b.radius * 2.0, b.height, 255, 60, 60, 35, false, false, 2, false, nil, nil, false)
            end
            if d2 > b.radius or math.abs(pc.z - b.center.z) > b.height then
                if not Run.outsideSince then Run.outsideSince = gt end
                local left = Config.Instance.boundaryGrace - (gt - Run.outsideSince) / 1000
                NUI.Send('boundary', { show = true, seconds = math.max(0, math.ceil(left)) })
                if left <= 0 then
                    Run.outsideSince = nil
                    NUI.Send('boundary', { show = false })
                    teleport(Run.start, true)
                end
            elseif Run.outsideSince then
                Run.outsideSince = nil
                NUI.Send('boundary', { show = false })
            end

            -- 敵HPバー
            for netId, e in pairs(Run.enemies) do
                if not e.boss and NetworkDoesNetworkIdExist(netId) then
                    local ent = NetworkGetEntityFromNetworkId(netId)
                    if DoesEntityExist(ent) then
                        local ec = GetEntityCoords(ent)
                        if #(ec - pc) < 45.0 then
                            local onScreen, sx, sy = GetScreenCoordFromWorldCoord(ec.x, ec.y, ec.z + 1.15)
                            if onScreen then
                                local w, h = 0.05, 0.007
                                local pct = math.max(0, math.min(1, e.hp / e.maxHp))
                                DrawRect(sx, sy, w + 0.002, h + 0.003, 0, 0, 0, 170)
                                DrawRect(sx - (w - w * pct) / 2, sy, w * pct, h, 230, 60, 60, 230)
                                draw3dText(ec.x, ec.y, ec.z + 1.32, e.label, 0.26)
                            end
                        end
                    end
                end
            end

            -- 範囲攻撃の予兆
            for id, a in pairs(Run.aoes) do
                local prog = math.min(1.0, (gt - a.startT) / math.max(1, a.endT - a.startT))
                DrawMarker(1, a.x, a.y, a.z - 0.5, 0, 0, 0, 0, 0, 0, a.radius * 2.0, a.radius * 2.0, 0.6, 255, 40, 40, 70, false, false, 2, false, nil, nil, false)
                DrawMarker(1, a.x, a.y, a.z - 0.45, 0, 0, 0, 0, 0, 0, a.radius * 2.0 * prog, a.radius * 2.0 * prog, 0.62, 255, 0, 0, 140, false, false, 2, false, nil, nil, false)
                if gt > a.endT + 3000 then Run.aoes[id] = nil end
            end

            -- スキルエフェクト
            for i = #Run.fx, 1, -1 do
                local f = Run.fx[i]
                if gt > f.untilT or not DoesEntityExist(f.ped) then table.remove(Run.fx, i)
                else
                    local c = GetEntityCoords(f.ped)
                    local r = f.radius and f.radius * 2.0 or 1.6
                    DrawMarker(25, c.x, c.y, c.z - 0.95, 0, 0, 0, 0, 0, 0, r, r, 1.0, f.color[1], f.color[2], f.color[3], 160, false, false, 2, false, nil, nil, false)
                end
            end

            -- インタラクト候補 (ドロップ / 目標)
            local best, bestD, bestKind
            if not Run.downed then
                for id, dr in pairs(Run.drops) do
                    local dd = #(pc - vector3(dr.x, dr.y, dr.z))
                    if dd < 40.0 then
                        local top = dr.items[1]
                        local r, g, bb = rarityColor(top and top.rarity)
                        DrawMarker(20, dr.x, dr.y, dr.z + 0.25 + math.sin(gt / 300) * 0.08, 0, 0, 0, 0, 180.0, 0, 0.35, 0.35, 0.35, r, g, bb, 210, false, true, 2, false, nil, nil, false)
                        DrawMarker(25, dr.x, dr.y, dr.z - 0.25, 0, 0, 0, 0, 0, 0, 0.9, 0.9, 0.5, r, g, bb, 120, false, false, 2, false, nil, nil, false)
                        if dd < Config.Instance.lootPickupRange and (not bestD or dd < bestD) then best, bestD, bestKind = dr, dd, 'drop' end
                    end
                end
                local o = Run.objective
                if o and o.targets then
                    for _, t in ipairs(o.targets) do
                        if not t.destroyed then
                            local dd = #(pc - vector3(t.x, t.y, t.z))
                            if dd < 80.0 then
                                DrawMarker(0, t.x, t.y, t.z + 2.2, 0, 0, 0, 0, 0, 0, 0.6, 0.6, 0.6, 255, 200, 40, 200, true, true, 2, false, nil, nil, false)
                                if dd < 25.0 then draw3dText(t.x, t.y, t.z + 1.6, t.label, 0.3) end
                            end
                            if dd < Config.Instance.interactRange and (not bestD or dd < bestD) then best, bestD, bestKind = t, dd, 'target' end
                        end
                    end
                end
            end

            if interacting then
                local it = interacting
                if not IsControlPressed(0, 38) or Run.downed or #(pc - vector3(it.t.x, it.t.y, it.t.z)) > Config.Instance.interactRange + 0.5 then
                    interacting = nil
                    NUI.Send('progress', { show = false })
                elseif gt >= it.endT then
                    interacting = nil
                    NUI.Send('progress', { show = false })
                    CreateThread(function()
                        local ok = lib.callback.await('projectin_rpg:interactFinish', false, it.t.id)
                        if not ok then NUI.Toast('失敗しました。もう一度試してください', 'error') end
                    end)
                end
            elseif best then
                if bestKind == 'drop' then
                    local names = {}
                    for _, i in ipairs(best.items) do names[#names + 1] = ('%s x%d'):format(i.label, i.count) end
                    help('~INPUT_CONTEXT~ 拾う: ' .. table.concat(names, ', '))
                    if IsControlJustReleased(0, 38) then
                        local id = best.id
                        CreateThread(function()
                            local ok, msg = lib.callback.await('projectin_rpg:pickup', false, id)
                            if ok then
                                PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
                                if msg then NUI.Toast(msg, 'info') end
                            else NUI.Toast(msg or '拾えませんでした', 'error') end
                        end)
                    end
                else
                    help(('~INPUT_CONTEXT~ 長押し: %s'):format(best.label))
                    if IsControlJustPressed(0, 38) then
                        local tgt = best
                        CreateThread(function()
                            local ok = lib.callback.await('projectin_rpg:interactStart', false, tgt.id)
                            if ok and IsControlPressed(0, 38) then
                                local dur = math.floor((Run and Run.objective.interactTime or 4) * 1000)
                                interacting = { t = tgt, endT = GetGameTimer() + dur }
                                NUI.Send('progress', { show = true, label = tgt.label, duration = dur })
                            end
                        end)
                    end
                end
            end
        end
    end
end)

-- HP をHUDへ (自分のHPはローカルで即時反映)
CreateThread(function()
    while true do
        if Run then
            local hp, max = RPGClient.MyHp()
            NUI.Send('selfHp', { hp = hp, maxHp = max, downed = Run.downed })
            Wait(250)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('projectin_rpg:client:refreshBlips', function()
    TriggerEvent('projectin_rpg:client:events', RPGClient.events)
end)
