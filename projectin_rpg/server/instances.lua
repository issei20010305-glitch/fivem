--[[
    インスタンス (ダンジョン/レイドの1回の攻略 = run)
    - パーティーごとに専用ルーティングバケットで隔離
    - 敵はサーバー生成 & サーバー権威HP
    - 退出/死亡/切断/再起動の全経路で通常状態へ復元
]]
Instances = {}
local U = RPG.Utils
local runs = {}          -- runId -> run
local playerRun = {}     -- src -> runId
local usedBuckets = {}
local counter = 0
math.randomseed(os.time())

local function now() return os.time() end

function Instances.GetRunOf(src)
    local id = playerRun[src]
    return id and runs[id] or nil
end

function Instances.GetRun(id) return runs[id] end
function Instances.All() return runs end

local function allocBucket()
    for b = Config.Instance.bucketStart, Config.Instance.bucketMax do
        if not usedBuckets[b] then
            usedBuckets[b] = true
            SetRoutingBucketPopulationEnabled(b, false)
            SetRoutingBucketEntityLockdownMode(b, Config.Instance.lockdownMode)
            return b
        end
    end
end

local function sendRun(run, event, data)
    for src, m in pairs(run.members) do
        if not m.left then TriggerClientEvent(event, src, data) end
    end
end
Instances.SendRun = sendRun

local function activeMembers(run)
    local out = {}
    for src, m in pairs(run.members) do if not m.left then out[#out + 1] = m end end
    return out
end
Instances.ActiveMembers = activeMembers

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end
Instances.PedCoords = pedCoords

---------------------------------------------------------------------------
-- HP (サーバーがネイティブ体力を読み取りRPG HPへ換算)
---------------------------------------------------------------------------
local HB = Config.Health
function Instances.RpgHp(src, member)
    local ped = GetPlayerPed(src)
    if ped == 0 then return 0 end
    local h = GetEntityHealth(ped)
    local hp = (h - 100 - HB.downedBuffer) / HB.nativeScale
    return U.clamp(math.floor(hp + 0.5), 0, member.maxHp)
end

---------------------------------------------------------------------------
-- HUD 同期
---------------------------------------------------------------------------
function Instances.PushParty(run)
    local list = {}
    local t = now()
    for _, src in ipairs(run.order) do
        local m = run.members[src]
        if m and not m.left then
            list[#list + 1] = {
                id = src, name = m.name, role = m.role, roleLabel = Config.Roles[m.role].label, color = Config.Roles[m.role].color,
                hp = Instances.RpgHp(src, m), maxHp = m.maxHp, downed = m.downed,
                mp = m.role == 'mage' and math.floor(m.mp) or nil, maxMp = m.role == 'mage' and Config.Mage.maxMp or nil,
                buff = (m.buff and m.buff.expires > t) and (m.buff.expires - t) or nil,
            }
        end
    end
    for src, m in pairs(run.members) do
        if not m.left then
            local cds = {}
            for k, v in pairs(m.cooldowns) do if v > t then cds[k] = v - t end end
            TriggerClientEvent('projectin_rpg:client:party', src, { members = list, me = { mp = m.mp and math.floor(m.mp), cooldowns = cds } })
        end
    end
end

local function objectiveText(run)
    local wave = run.def.waves[run.wave]
    if not wave then return '', '' end
    local o = wave.objective
    if o.type == 'kill_all' then
        local alive = 0
        for _, e in pairs(run.enemies) do if e.alive and e.wave == run.wave and not e.isAdd then alive = alive + 1 end end
        return '敵を全滅させる', ('残り %d 体'):format(alive)
    elseif o.type == 'kill_count' then
        return ('敵を%d体倒す'):format(o.count), ('%d / %d'):format(math.min(run.waveKills, o.count), o.count)
    elseif o.type == 'interact' then
        local done = 0
        for _, id in ipairs(o.targets) do if run.props[id] and run.props[id].destroyed then done = done + 1 end end
        return o.label, ('%d / %d'):format(done, #o.targets)
    elseif o.type == 'survive' then
        local left = math.max(0, (run.waveStartedAt + o.duration) - now())
        return ('%d秒間生き残る'):format(o.duration), ('残り %d 秒'):format(left)
    elseif o.type == 'boss' then
        return 'ボスを討伐する', ''
    end
    return '', ''
end

function Instances.PushObjective(run)
    local wave = run.def.waves[run.wave]
    local title, progress = objectiveText(run)
    local targets
    if wave and wave.objective.type == 'interact' and run.waveState == 'running' then
        targets = {}
        for _, id in ipairs(wave.objective.targets) do
            local p = run.props[id]
            if p then targets[#targets + 1] = { id = id, label = p.def.label, x = p.def.x, y = p.def.y, z = p.def.z, destroyed = p.destroyed } end
        end
    end
    local boss
    if run.boss and run.boss.enemy then
        local e = run.boss.enemy
        local ph = run.def.boss.phases[run.boss.phase]
        boss = { label = e.def.label, hp = math.max(0, math.floor(e.hp)), maxHp = e.maxHp, phase = ph and ph.label or '', alive = e.alive }
    end
    sendRun(run, 'projectin_rpg:client:objective', {
        wave = run.wave, waveCount = #run.def.waves, waveLabel = wave and wave.label or '',
        state = run.waveState, title = title, progress = progress, targets = targets, boss = boss,
        timeLeft = math.max(0, run.endsAt - now()), interactTime = wave and wave.objective.interactTime,
    })
end

local enemyPushPending = {}
function Instances.PushEnemies(run, immediate)
    if enemyPushPending[run.id] and not immediate then return end
    enemyPushPending[run.id] = true
    SetTimeout(immediate and 0 or 250, function()
        enemyPushPending[run.id] = nil
        if not runs[run.id] then return end
        local list = {}
        for netId, e in pairs(run.enemies) do
            if e.alive then
                list[#list + 1] = { netId = netId, hp = math.floor(e.hp), maxHp = e.maxHp, label = e.def.label, boss = e.isBoss }
            end
        end
        sendRun(run, 'projectin_rpg:client:enemies', list)
    end)
end

---------------------------------------------------------------------------
-- エンティティ生成
---------------------------------------------------------------------------
local function waitExists(entity)
    local t = GetGameTimer()
    while not DoesEntityExist(entity) do
        Wait(10)
        if GetGameTimer() - t > 2000 then return false end
    end
    return true
end

local function spawnPoint(run, id)
    for _, sp in ipairs(run.def.spawnPoints) do if sp.id == id then return sp end end
    return run.def.spawnPoints[1]
end

local function aliveCount(run)
    local n = 0
    for _, e in pairs(run.enemies) do if e.alive then n = n + 1 end end
    return n
end

function Instances.SpawnEnemy(run, key, spId, opts)
    if not runs[run.id] or run.state ~= 'active' then return nil end
    if aliveCount(run) >= Config.Instance.maxAliveEnemies then return nil end
    local def = run.def.enemies[key]
    if not def then return nil end
    local sp = spawnPoint(run, spId)
    local jitter = opts.isBoss and 0.0 or 2.0
    local x = sp.x + (math.random() - 0.5) * jitter * 2
    local y = sp.y + (math.random() - 0.5) * jitter * 2
    local ped = CreatePed(4, GetHashKey(def.model), x, y, sp.z, sp.h or 0.0, true, true)
    if not ped or ped == 0 or not waitExists(ped) then
        print(('[projectin_rpg] ^3敵の生成に失敗しました (model=%s)。モデル名を確認してください^0'):format(def.model))
        return nil
    end
    SetEntityRoutingBucket(ped, run.bucket)
    if SetEntityOrphanMode then SetEntityOrphanMode(ped, 2) end
    if def.weapon ~= 'WEAPON_UNARMED' then GiveWeaponToPed(ped, GetHashKey(def.weapon), 9999, false, true) end
    if def.armor > 0 then SetPedArmour(ped, def.armor) end
    local netId = NetworkGetNetworkIdFromEntity(ped)
    local hp = math.floor(def.hp * run.hpScale)
    local enemy = {
        netId = netId, entity = ped, key = key, def = def, hp = hp, maxHp = hp, alive = true,
        isBoss = opts.isBoss or false, wave = run.wave, group = opts.group, isAdd = opts.isAdd, respawn = opts.respawn, spawn = spId,
        damageTakenMult = 1.0, spawnedAt = GetGameTimer(),
    }
    run.enemies[netId] = enemy
    Entity(ped).state:set('rpgEnemy', {
        run = run.id, label = def.label, weapon = def.weapon, accuracy = def.accuracy, boss = enemy.isBoss,
    }, true)
    return enemy
end

local function spawnProps(run)
    for _, p in ipairs(run.def.props) do
        local obj = CreateObjectNoOffset(GetHashKey(p.model), p.x, p.y, p.z, true, true, false)
        if obj and obj ~= 0 and waitExists(obj) then
            SetEntityRoutingBucket(obj, run.bucket)
            SetEntityHeading(obj, p.h or 0.0)
            FreezeEntityPosition(obj, true)
            Entity(obj).state:set('rpgProp', { run = run.id, id = p.id }, true)
            run.props[p.id] = { entity = obj, def = p, destroyed = false }
        else
            run.props[p.id] = { entity = nil, def = p, destroyed = false }
        end
    end
end

local function deleteEntity(e)
    if e and DoesEntityExist(e) then DeleteEntity(e) end
end

---------------------------------------------------------------------------
-- 撃破・ドロップ
---------------------------------------------------------------------------
local function rollLoot(list)
    local out = {}
    for _, r in ipairs(list or {}) do
        if math.random() * 100 <= r.chance then
            out[#out + 1] = { name = r.item, count = U.randomInt(r.min, r.max) }
        end
    end
    return out
end
Instances.RollLoot = rollLoot

function Instances.KillEnemy(run, enemy, killerSrc, noLoot)
    if not enemy.alive then return end
    enemy.alive = false
    enemy.hp = 0
    if DoesEntityExist(enemy.entity) then
        Entity(enemy.entity).state:set('rpgDead', true, true)
        local ent = enemy.entity
        SetTimeout(8000, function() deleteEntity(ent) end)
    end
    if enemy.wave == run.wave then run.waveKills = run.waveKills + 1 end
    local killer = killerSrc and run.members[killerSrc]
    if killer then
        killer.kills = killer.kills + 1
        if not run.testMode then Chars.AddStat(killer.cid, 'kills', 1) end
    end
    -- 個人ドロップ (メンバーごとに個別抽選。他人のドロップは見えない/拾えない)
    if not noLoot and #enemy.def.loot > 0 then
        local c = GetEntityCoords(enemy.entity)
        for src, m in pairs(run.members) do
            if not m.left then
                local items = rollLoot(enemy.def.loot)
                if #items > 0 then
                    run.dropSeq = run.dropSeq + 1
                    local drop = { id = run.dropSeq, owner = src, items = items, x = c.x, y = c.y, z = c.z, claimed = false }
                    run.drops[drop.id] = drop
                    local preview = {}
                    for _, it in ipairs(items) do
                        local d = RPG.Items[it.name]
                        preview[#preview + 1] = { label = d.label, icon = d.icon, count = it.count, rarity = d.rarity }
                    end
                    TriggerClientEvent('projectin_rpg:client:dropAdded', src, { id = drop.id, x = c.x, y = c.y, z = c.z, items = preview })
                end
            end
        end
    end
    if enemy.isBoss then
        sendRun(run, 'projectin_rpg:client:banner', { title = '討伐成功！', text = enemy.def.label .. 'を撃破した！', kind = 'success' })
    end
    -- respawn グループ (survive用)
    if enemy.respawn and run.waveState == 'running' and enemy.wave == run.wave then
        local spawns = run.def.waves[run.wave].groups[enemy.group].spawn
        SetTimeout(3500, function()
            if runs[run.id] and run.state == 'active' and run.waveState == 'running' and enemy.wave == run.wave then
                Instances.SpawnEnemy(run, enemy.key, spawns[math.random(#spawns)], { group = enemy.group, respawn = true })
                Instances.PushEnemies(run)
            end
        end)
    end
    Instances.PushEnemies(run)
    Instances.PushObjective(run)
end

function Instances.PickupDrop(src, dropId)
    local run = Instances.GetRunOf(src)
    if not run or (run.state ~= 'active' and run.state ~= 'results') then return false, '取得できません' end
    local drop = run.drops[tonumber(dropId) or -1]
    if not drop or drop.owner ~= src then return false, 'そのドロップは存在しません' end
    if drop.claimed or drop.pending then return false, '取得済みです' end
    local pc = pedCoords(src)
    if not pc or #(pc - vector3(drop.x, drop.y, drop.z)) > Config.Instance.lootPickupRange + 1.5 then return false, '距離が遠すぎます' end
    drop.pending = true
    if run.testMode then
        drop.claimed = true
        drop.pending = nil
        TriggerClientEvent('projectin_rpg:client:dropRemoved', src, drop.id)
        return true, 'テストモードのため実際には付与されません'
    end
    local ok, err = RpgInv.Grant(src, drop.items, { claimKey = ('%s:drop:%d'):format(run.id, drop.id), overflow = false })
    drop.pending = nil
    if ok then
        drop.claimed = true
        run.members[src].loot = run.members[src].loot or {}
        for _, it in ipairs(drop.items) do table.insert(run.members[src].loot, it) end
        TriggerClientEvent('projectin_rpg:client:dropRemoved', src, drop.id)
        return true
    elseif err == 'duplicate' then
        drop.claimed = true
        TriggerClientEvent('projectin_rpg:client:dropRemoved', src, drop.id)
        return false, '取得済みです'
    elseif err == 'full' then
        return false, 'RPGインベントリがいっぱいです'
    end
    return false, '取得に失敗しました'
end

---------------------------------------------------------------------------
-- ウェーブ進行
---------------------------------------------------------------------------
local finishRun

local function enterBossPhase(run, index)
    local ph = run.def.boss.phases[index]
    if not ph then return end
    run.boss.phase = index
    local e = run.boss.enemy
    e.damageTakenMult = ph.damageTakenMult or 1.0
    if ph.accuracy and DoesEntityExist(e.entity) then
        local st = Entity(e.entity).state.rpgEnemy or {}
        st.accuracy = ph.accuracy
        Entity(e.entity).state:set('rpgEnemy', st, true)
    end
    run.boss.nextAoeAt = ph.aoe and (now() + math.max(3, ph.aoe.interval // 2)) or nil
    sendRun(run, 'projectin_rpg:client:banner', { title = ph.label, text = ph.message ~= '' and ph.message or e.def.label, kind = 'boss' })
    if ph.adds then
        CreateThread(function()
            for i = 1, ph.adds.count do
                Instances.SpawnEnemy(run, ph.adds.enemy, ph.adds.spawn[((i - 1) % #ph.adds.spawn) + 1], { isAdd = true })
                Wait(150)
            end
            Instances.PushEnemies(run)
        end)
    end
end

function Instances.CheckBossPhase(run)
    local b = run.boss
    if not b or not b.enemy or not b.enemy.alive then return end
    local pct = b.enemy.hp / b.enemy.maxHp * 100
    local phases = run.def.boss.phases
    while phases[b.phase + 1] and pct <= phases[b.phase + 1].hpPct do
        enterBossPhase(run, b.phase + 1)
    end
end

local function startWave(run, index)
    local wave = run.def.waves[index]
    if not wave then return finishRun(run, 'clear') end
    run.wave = index
    run.waveState = 'delay'
    run.waveKills = 0
    sendRun(run, 'projectin_rpg:client:banner', { title = wave.label, text = wave.message, kind = 'wave' })
    Instances.PushObjective(run)
    SetTimeout(math.floor(wave.delay * 1000), function()
        if not runs[run.id] or run.state ~= 'active' or run.wave ~= index then return end
        run.waveState = 'running'
        run.waveStartedAt = now()
        CreateThread(function()
            for gi, g in ipairs(wave.groups) do
                for i = 1, g.count do
                    Instances.SpawnEnemy(run, g.enemy, g.spawn[((i - 1) % #g.spawn) + 1], { group = gi, respawn = g.respawn })
                    Wait(120)
                end
            end
            if wave.objective.type == 'boss' and run.def.boss then
                local e = Instances.SpawnEnemy(run, run.def.boss.enemy, run.def.boss.spawn, { isBoss = true })
                if e then
                    run.boss = { enemy = e, phase = 0 }
                    enterBossPhase(run, 1)
                else
                    -- モデル不正などで生成できない場合はウェーブを飛ばす(進行不能防止)
                    sendRun(run, 'projectin_rpg:client:banner', { title = 'エラー', text = 'ボスを生成できませんでした', kind = 'error' })
                    run.bossSpawnFailed = true
                end
            end
            Instances.PushEnemies(run, true)
            Instances.PushObjective(run)
        end)
    end)
end

local function waveComplete(run)
    local wave = run.def.waves[run.wave]
    local o = wave.objective
    if run.waveState ~= 'running' then return false end
    if now() - run.waveStartedAt < 2 then return false end -- 生成待ち
    if o.type == 'kill_all' then
        for _, e in pairs(run.enemies) do if e.alive and e.wave == run.wave and not e.isAdd then return false end end
        return true
    elseif o.type == 'kill_count' then
        return run.waveKills >= o.count
    elseif o.type == 'interact' then
        for _, id in ipairs(o.targets) do if not (run.props[id] and run.props[id].destroyed) then return false end end
        return true
    elseif o.type == 'survive' then
        return now() >= run.waveStartedAt + o.duration
    elseif o.type == 'boss' then
        if run.bossSpawnFailed then return true end
        return run.boss and run.boss.enemy and not run.boss.enemy.alive
    end
    return false
end

local function onWaveCleared(run)
    run.waveState = 'cleared'
    -- 残った敵は撤退(ドロップなし)
    for _, e in pairs(run.enemies) do
        if e.alive then Instances.KillEnemy(run, e, nil, true) end
    end
    if HB.downedAutoReviveOnWaveClear then
        for src, m in pairs(run.members) do
            if not m.left and m.downed then Combat.Revive(run, src, HB.waveClearRevivePct) end
        end
    end
    sendRun(run, 'projectin_rpg:client:banner', { title = 'ウェーブクリア！', text = run.def.waves[run.wave].label, kind = 'success' })
    local nextIndex = run.wave + 1
    SetTimeout(3000, function()
        if runs[run.id] and run.state == 'active' then startWave(run, nextIndex) end
    end)
end

---------------------------------------------------------------------------
-- 開始
---------------------------------------------------------------------------
--- @param def table サニタイズ済み定義
--- @param players number[]
--- @param opts table { defId, testMode, eventId, roleOverride = { [src] = role } }
function Instances.Start(def, players, opts)
    opts = opts or {}
    for _, src in ipairs(players) do
        if playerRun[src] then return false, ('%s は既に参加中です'):format(Bridge.GetName(src)) end
    end
    local bucket = allocBucket()
    if not bucket then return false, '空きインスタンスがありません。しばらくお待ちください' end
    counter = counter + 1
    local run = {
        id = ('%x%04x%02x'):format(now(), math.random(0, 0xffff), counter % 256),
        defId = opts.defId, def = def, name = def.name, type = def.type, testMode = opts.testMode == true, eventId = opts.eventId,
        bucket = bucket, state = 'starting', members = {}, order = {}, enemies = {}, props = {}, drops = {}, dropSeq = 0,
        wave = 0, waveState = 'delay', waveKills = 0, startedAt = now(), endsAt = now() + def.timeLimit + 15,
        hpScale = 1 + math.max(0, #players - 1) * (def.type == 'raid' and 0.3 or 0.4),
    }
    runs[run.id] = run

    -- メンバー登録と所持品退避
    local held = {}
    local entryPos = def.exit or def.entry
    for _, src in ipairs(players) do
        local cid = Bridge.GetCitizenId(src)
        local c = cid and Chars.Load(cid)
        local role = (opts.roleOverride and opts.roleOverride[src]) or (c and c.role)
        if not cid or not role or not Config.Roles[role] then
            for _, s in ipairs(held) do Holding.Restore(s) playerRun[s] = nil end
            runs[run.id] = nil usedBuckets[bucket] = nil
            return false, ('%s のロールが未選択です'):format(Bridge.GetName(src))
        end
        local pc = pedCoords(src)
        local returnPos = { x = entryPos.x, y = entryPos.y, z = entryPos.z, h = entryPos.h or 0.0 }
        if pc and not opts.testMode then
            -- 入口付近にいた場合はその場所へ戻す
            if #(pc - vector3(def.entry.x, def.entry.y, def.entry.z)) < 60.0 then
                returnPos = { x = pc.x, y = pc.y, z = pc.z, h = GetEntityHeading(GetPlayerPed(src)) }
            end
        elseif pc then
            returnPos = { x = pc.x, y = pc.y, z = pc.z, h = GetEntityHeading(GetPlayerPed(src)) }
        end
        playerRun[src] = run.id -- フック判定のため先に登録
        local ok, info = Holding.Hold(src, run.id, returnPos, role)
        if not ok then
            playerRun[src] = nil
            for _, s in ipairs(held) do Holding.Restore(s) playerRun[s] = nil end
            runs[run.id] = nil usedBuckets[bucket] = nil
            return false, ('%s: %s'):format(Bridge.GetName(src), info)
        end
        held[#held + 1] = src
        local roleDef = Config.Roles[role]
        run.members[src] = {
            src = src, cid = cid, name = Bridge.GetName(src), role = role,
            maxHp = math.floor(HB.baseHp * roleDef.hpMult), mp = role == 'mage' and Config.Mage.maxMp or nil,
            downed = false, cooldowns = {}, kills = 0, damage = 0, healing = 0, downs = 0, loot = {},
            returnPos = returnPos, outsideSince = nil, lastHit = {}, left = false,
        }
        run.order[#run.order + 1] = src
    end

    -- バケット移動とクライアント入場
    for _, src in ipairs(run.order) do
        local m = run.members[src]
        local roleDef = Config.Roles[m.role]
        SetPlayerRoutingBucket(src, bucket)
        Player(src).state:set('rpgRun', run.id, true)
        Parties.Push(Parties.Get(src))
        local skills
        if m.role == 'mage' then
            skills = {}
            for k, s in pairs(Config.Mage.skills) do skills[#skills + 1] = { id = k, key = s.key, label = s.label, mp = s.mp, cooldown = s.cooldown, target = s.target } end
            table.sort(skills, function(a, b) return a.key < b.key end)
        end
        TriggerClientEvent('projectin_rpg:client:enterRun', src, {
            runId = run.id, name = def.name, type = def.type, testMode = run.testMode,
            start = def.start, boundary = def.boundary, ipls = def.ipls, timeLimit = def.timeLimit,
            role = m.role, roleLabel = roleDef.label, canAttack = roleDef.canAttack, maxHp = m.maxHp,
            downedBuffer = HB.downedBuffer, nativeScale = HB.nativeScale, skills = skills, maxMp = Config.Mage.maxMp,
        })
        if not run.testMode then Chars.AddStat(m.cid, 'runs', 1) end
    end
    Bridge.Log(nil, 'run_start', { run = run.id, def = opts.defId, name = def.name, players = #run.order, test = run.testMode })

    CreateThread(function()
        spawnProps(run)
        Wait(4000)
        if not runs[run.id] then return end
        run.state = 'active'
        run.startedAt = now()
        run.endsAt = now() + def.timeLimit
        startWave(run, 1)
        Instances.PushParty(run)
    end)
    return true, run
end

---------------------------------------------------------------------------
-- 終了・退出
---------------------------------------------------------------------------
local function destroyRun(run)
    for _, e in pairs(run.enemies) do deleteEntity(e.entity) end
    for _, p in pairs(run.props) do deleteEntity(p.entity) end
    usedBuckets[run.bucket] = nil
    runs[run.id] = nil
    enemyPushPending[run.id] = nil
end

--- プレイヤーを退出させ通常状態へ復元
--- @param reason string 'leave'|'results'|'drop'|'logout'|'admin'|'stop'
function Instances.Leave(src, reason)
    local run = Instances.GetRunOf(src)
    if not run then return false end
    local m = run.members[src]
    if not m or m.left then playerRun[src] = nil return false end
    m.left = true
    m.leftReason = reason
    playerRun[src] = nil

    if reason == 'drop' then
        -- 切断時: インベントリはox_inventory側でアンロード中のため触らず、次回ログイン時に復元
        Bridge.Log(m.cid, 'run_leave', { run = run.id, reason = reason })
    elseif reason == 'stop' then
        Holding.Restore(src, true)
        SetPlayerRoutingBucket(src, 0)
        local ped = GetPlayerPed(src)
        if ped ~= 0 then SetEntityCoords(ped, m.returnPos.x, m.returnPos.y, m.returnPos.z, false, false, false, false) end
        Player(src).state:set('rpgRun', nil, true)
    else
        local row = Holding.Restore(src)
        SetPlayerRoutingBucket(src, 0)
        Player(src).state:set('rpgRun', nil, true)
        local pos = (row and row.return_pos) or m.returnPos
        TriggerClientEvent('projectin_rpg:client:exitRun', src, {
            pos = pos, health = row and row.health or 200, armour = row and row.armour or 0, reason = reason,
        })
        Parties.Push(Parties.Get(src))
        Bridge.Log(m.cid, 'run_leave', { run = run.id, reason = reason })
    end

    -- 生存メンバーが居なくなったら終了
    if #activeMembers(run) == 0 then
        if run.state == 'active' or run.state == 'starting' then
            run.result = run.result or 'abandoned'
            MySQL.insert('INSERT INTO rpg_run_history (run_id, definition_id, name, result, duration, players, test_mode) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                run.id, run.defId, run.name, run.result, now() - run.startedAt, json.encode(run.order), run.testMode and 1 or 0,
            })
        end
        destroyRun(run)
    elseif run.state == 'active' then
        Instances.CheckWipe(run)
        Instances.PushParty(run)
    end
    return true
end

function Instances.CheckWipe(run)
    if run.state ~= 'active' then return end
    local any = false
    for _, m in pairs(run.members) do
        if not m.left and not m.downed then any = true break end
    end
    if not any then finishRun(run, 'wipe') end
end

finishRun = function(run, result)
    if run.state ~= 'active' then return end
    run.state = 'results'
    run.result = result
    local success = result == 'clear'
    for _, e in pairs(run.enemies) do
        if e.alive then
            e.alive = false
            if DoesEntityExist(e.entity) then Entity(e.entity).state:set('rpgDead', true, true) end
        end
    end
    Instances.PushEnemies(run, true)
    local duration = now() - run.startedAt

    CreateThread(function()
        local results = {}
        for _, src in ipairs(run.order) do
            local m = run.members[src]
            if m and not m.left then
                local rewards = {}
                if success then
                    rewards = rollLoot(run.def.rewards.clear)
                    -- 未回収の個人ドロップを自動回収
                    if Config.Instance.unclaimedLootOnClear == 'auto' then
                        for _, d in pairs(run.drops) do
                            if d.owner == src and not d.claimed and not d.pending then
                                d.claimed = true
                                for _, it in ipairs(d.items) do rewards[#rewards + 1] = it end
                            end
                        end
                    end
                    if not run.testMode and #rewards > 0 then
                        local ok, res = RpgInv.Grant(src, rewards, { claimKey = ('%s:clear:%s'):format(run.id, m.cid), overflow = true })
                        if ok and res.overflowed and #res.overflowed > 0 then
                            Bridge.Notify(src, '容量不足のため一部の報酬を「受取箱」へ送りました(/rpg → インベントリ)', 'warning', 9000)
                        elseif not ok then
                            rewards = {}
                        end
                    end
                    if not run.testMode then Chars.AddStat(m.cid, run.type == 'raid' and 'raidClears' or 'dungeonClears', 1) end
                    TriggerClientEvent('projectin_rpg:client:dropsClear', src)
                end
                if not run.testMode then
                    local c = Chars.Get(m.cid)
                    if c then Chars.SaveStats(c) end
                end
                local all = {}
                for _, it in ipairs(m.loot) do all[#all + 1] = it end
                for _, it in ipairs(rewards) do all[#all + 1] = it end
                local view = {}
                for _, it in ipairs(all) do
                    local d = RPG.Items[it.name]
                    if d then view[#view + 1] = { label = d.label, icon = d.icon, count = it.count, rarity = d.rarity } end
                end
                results[#results + 1] = { id = src, name = m.name, role = m.role, roleLabel = Config.Roles[m.role].label,
                    kills = m.kills, damage = math.floor(m.damage), healing = math.floor(m.healing), downs = m.downs, rewards = view }
            end
        end
        local mvp, best = nil, -1
        for _, r in ipairs(results) do
            local score = r.damage + r.healing * 1.5 + r.kills * 50
            if score > best then best, mvp = score, r.id end
        end
        local resultLabel = ({ clear = 'クリア', wipe = '全滅', timeout = '時間切れ', admin = '強制終了' })[result] or result
        for _, r in ipairs(results) do
            TriggerClientEvent('projectin_rpg:client:results', r.id, {
                success = success, result = result, resultLabel = resultLabel, name = run.name, type = run.type, duration = duration,
                players = results, mvp = mvp, testMode = run.testMode, autoLeave = Config.Instance.resultsAutoLeave,
            })
        end
        MySQL.insert('INSERT INTO rpg_run_history (run_id, definition_id, name, result, duration, players, test_mode) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            run.id, run.defId, run.name, result, duration, json.encode(results), run.testMode and 1 or 0,
        })
        Bridge.Log(nil, 'run_end', { run = run.id, result = result, duration = duration })
        SetTimeout(Config.Instance.resultsAutoLeave * 1000, function()
            if not runs[run.id] then return end
            for src, m in pairs(run.members) do
                if not m.left then Instances.Leave(src, 'results') end
            end
        end)
    end)
end

function Instances.ForceEnd(runId, adminSrc)
    local run = runs[runId]
    if not run then return false end
    Bridge.Log(Bridge.GetCitizenId(adminSrc) or adminSrc, 'run_force_end', { run = runId })
    if run.state == 'active' then finishRun(run, 'admin') return true end
    for src, m in pairs(run.members) do if not m.left then Instances.Leave(src, 'admin') end end
    return true
end

---------------------------------------------------------------------------
-- インタラクト目標
---------------------------------------------------------------------------
function Instances.InteractStart(src, propId)
    local run = Instances.GetRunOf(src)
    if not run or run.state ~= 'active' or run.waveState ~= 'running' then return false end
    local m = run.members[src]
    if not m or m.downed then return false end
    local wave = run.def.waves[run.wave]
    if wave.objective.type ~= 'interact' then return false end
    local valid = false
    for _, id in ipairs(wave.objective.targets) do if id == propId then valid = true end end
    local p = run.props[propId]
    if not valid or not p or p.destroyed then return false end
    local pc = pedCoords(src)
    if not pc or #(pc - vector3(p.def.x, p.def.y, p.def.z)) > Config.Instance.interactRange + 1.5 then return false end
    m.interacting = { id = propId, at = GetGameTimer() }
    return true
end

function Instances.InteractFinish(src, propId)
    local run = Instances.GetRunOf(src)
    if not run or run.state ~= 'active' then return false end
    local m = run.members[src]
    if not m or m.downed or not m.interacting or m.interacting.id ~= propId then return false end
    local wave = run.def.waves[run.wave]
    local need = (wave.objective.interactTime or 4) * 1000 - 400
    if GetGameTimer() - m.interacting.at < need then return false end
    m.interacting = nil
    local p = run.props[propId]
    if not p or p.destroyed then return false end
    local pc = pedCoords(src)
    if not pc or #(pc - vector3(p.def.x, p.def.y, p.def.z)) > Config.Instance.interactRange + 2.0 then return false end
    p.destroyed = true
    sendRun(run, 'projectin_rpg:client:propDestroyed', { id = propId, x = p.def.x, y = p.def.y, z = p.def.z })
    local ent = p.entity
    SetTimeout(600, function() deleteEntity(ent) end)
    Instances.PushObjective(run)
    return true
end

---------------------------------------------------------------------------
-- メインループ
---------------------------------------------------------------------------
CreateThread(function()
    local tick = 0
    while true do
        Wait(500)
        tick = tick + 1
        local t = now()
        for _, run in pairs(runs) do
            if run.state == 'active' then
                -- 時間切れ
                if t >= run.endsAt then
                    finishRun(run, 'timeout')
                else
                    -- ネイティブ死亡/消失した敵の処理 (ドロップなし)
                    for netId, e in pairs(run.enemies) do
                        if e.alive and GetGameTimer() - e.spawnedAt > 3000 then
                            if not DoesEntityExist(e.entity) then
                                Instances.KillEnemy(run, e, nil, true)
                                run.enemies[netId] = nil
                            elseif GetEntityHealth(e.entity) <= 0 then
                                Instances.KillEnemy(run, e, nil, true)
                            end
                        end
                    end
                    -- 完全に消えた死亡敵の掃除
                    if tick % 20 == 0 then
                        for netId, e in pairs(run.enemies) do
                            if not e.alive and not DoesEntityExist(e.entity) then run.enemies[netId] = nil end
                        end
                    end
                    if run.waveState == 'running' and waveComplete(run) then onWaveCleared(run) end
                    Combat.Tick(run, t)
                    if tick % 2 == 0 then
                        Instances.PushParty(run)
                        Instances.PushObjective(run)
                    end
                    -- 境界チェック (サーバー側)
                    if tick % 4 == 0 then
                        local b = run.def.boundary
                        local center = vector3(b.center.x, b.center.y, b.center.z)
                        for src, m in pairs(run.members) do
                            if not m.left then
                                local pc = pedCoords(src)
                                if pc then
                                    local out = #(vector2(pc.x, pc.y) - vector2(center.x, center.y)) > b.radius + 10.0
                                        or math.abs(pc.z - center.z) > b.height + 10.0
                                    if out then
                                        m.outsideSince = m.outsideSince or t
                                        if t - m.outsideSince > Config.Instance.boundaryGrace + 4 then
                                            local s = run.def.start
                                            SetEntityCoords(GetPlayerPed(src), s.x, s.y, s.z, false, false, false, false)
                                            TriggerClientEvent('projectin_rpg:client:teleportStart', src)
                                            m.outsideSince = nil
                                        end
                                    else
                                        m.outsideSince = nil
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- 停止時の安全な復元
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, run in pairs(runs) do
        for src, m in pairs(run.members) do
            if not m.left then Instances.Leave(src, 'stop') end
        end
        for _, e in pairs(run.enemies) do deleteEntity(e.entity) end
        for _, p in pairs(run.props) do deleteEntity(p.entity) end
    end
end)
