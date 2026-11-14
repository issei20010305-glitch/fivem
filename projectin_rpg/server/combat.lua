--[[
    サーバー権威の戦闘処理
    - 命中報告はサーバーで「参加中 / 攻撃可能ロール / 武器一致 / 発射間隔 / 射程 / 敵の所属」を検証
    - ダメージ計算は全てサーバー側 (ロール倍率・バフ・ボス被ダメ倍率)
    - 魔導士スキルはMP/クールダウン/射程/対象をサーバーで検証
]]
Combat = {}
local U = RPG.Utils
local weaponByHash = {}
for name, w in pairs(Config.Weapons) do weaponByHash[GetHashKey(name)] = { name = name, data = w } end
-- ox_inventory の数値ハッシュは符号付きの場合があるため両方登録
for hash, w in pairs(U.deepcopy(weaponByHash)) do
    if hash < 0 then weaponByHash[hash + 4294967296] = w else weaponByHash[hash - 4294967296] = w end
end

local loanerAllowed = {}
for role, def in pairs(Config.Roles) do
    loanerAllowed[role] = { [GetHashKey('WEAPON_UNARMED')] = true }
    for _, l in ipairs(def.loadout) do
        if l.item:sub(1, 7) == 'WEAPON_' then
            local h = GetHashKey(l.item)
            loanerAllowed[role][h] = true
            loanerAllowed[role][h < 0 and h + 4294967296 or h - 4294967296] = true
        end
    end
end

local function flag(src, why)
    Bridge.Log(Bridge.GetCitizenId(src) or src, 'combat_reject', { why = why })
end

--- 命中報告
RegisterNetEvent('projectin_rpg:server:hit', function(netId, weaponHash, headshot)
    local src = source
    local run = Instances.GetRunOf(src)
    if not run or run.state ~= 'active' then return end
    local m = run.members[src]
    if not m or m.downed then return end
    local roleDef = Config.Roles[m.role]
    if not roleDef.canAttack then return flag(src, 'mage_attack') end

    netId = tonumber(netId)
    local enemy = netId and run.enemies[netId]
    if not enemy or not enemy.alive then return end

    weaponHash = tonumber(weaponHash)
    local w = weaponHash and weaponByHash[weaponHash]
    if not w then return end
    if not loanerAllowed[m.role][weaponHash] then return flag(src, 'weapon_not_allowed') end

    -- 実際に構えている武器と一致するか (近接/素手は判定がブレるため緩和)
    local ped = GetPlayerPed(src)
    local selected = GetSelectedPedWeapon(ped)
    if selected ~= weaponHash and w.name ~= 'WEAPON_UNARMED' then
        local alt = selected < 0 and selected + 4294967296 or selected - 4294967296
        if alt ~= weaponHash then return end
    end

    -- 発射間隔
    local t = GetGameTimer()
    local last = m.lastHit[w.name] or 0
    if t - last < w.data.interval * 0.85 then return end
    m.lastHit[w.name] = t

    -- 射程
    if not DoesEntityExist(enemy.entity) then return end
    local dist = #(GetEntityCoords(ped) - GetEntityCoords(enemy.entity))
    if dist > w.data.range + Config.MaxHitDistancePadding then return flag(src, ('range %.1f'):format(dist)) end

    local mult = roleDef.damageMult
    if m.buff and m.buff.expires > os.time() then mult = mult * (1 + m.buff.bonus) end
    local dmg = w.data.damage * mult
    if headshot == true then dmg = dmg * Config.HeadshotMult end
    dmg = dmg * (enemy.damageTakenMult or 1.0) * (1 - (enemy.def.damageReduction or 0))
    dmg = math.max(1, dmg)

    enemy.hp = enemy.hp - dmg
    m.damage = m.damage + dmg
    if enemy.hp <= 0 then
        Instances.KillEnemy(run, enemy, src, false)
    else
        if enemy.isBoss then Instances.CheckBossPhase(run) end
        Instances.PushEnemies(run)
    end
end)

--- プレイヤーのダウン報告 (サーバー側で体力を読み取り妥当性を確認)
RegisterNetEvent('projectin_rpg:server:downed', function()
    local src = source
    local run = Instances.GetRunOf(src)
    if not run or run.state ~= 'active' then return end
    local m = run.members[src]
    if not m or m.downed then return end
    local h = GetEntityHealth(GetPlayerPed(src))
    if h > 100 + Config.Health.downedBuffer + 25 then return end -- 体力が残っている報告は無視
    m.downed = true
    m.downs = m.downs + 1
    m.downedAt = os.time()
    Instances.SendRun(run, 'projectin_rpg:client:memberDowned', { id = src, name = m.name })
    Instances.PushParty(run)
    Instances.CheckWipe(run)
end)

function Combat.HealMember(run, targetSrc, pct, healerSrc)
    local t = run.members[targetSrc]
    if not t or t.left or t.downed then return 0 end
    local amount = math.floor(t.maxHp * pct)
    TriggerClientEvent('projectin_rpg:client:heal', targetSrc, amount)
    local healer = healerSrc and run.members[healerSrc]
    if healer and healerSrc ~= targetSrc then
        local missing = t.maxHp - Instances.RpgHp(targetSrc, t)
        healer.healing = healer.healing + math.min(amount, math.max(0, missing))
    end
    return amount
end

function Combat.Revive(run, targetSrc, hpPct)
    local t = run.members[targetSrc]
    if not t or t.left or not t.downed then return false end
    t.downed = false
    t.downedAt = nil
    TriggerClientEvent('projectin_rpg:client:revive', targetSrc, math.max(1, math.floor(t.maxHp * hpPct)))
    Instances.SendRun(run, 'projectin_rpg:client:toast', { message = ('%s が復活しました'):format(t.name), type = 'success' })
    Instances.PushParty(run)
    return true
end

---------------------------------------------------------------------------
-- 魔導士スキル
---------------------------------------------------------------------------
function Combat.UseSkill(src, skillId, targetSrc)
    local run = Instances.GetRunOf(src)
    if not run or run.state ~= 'active' then return false, 'ダンジョン/レイド内でのみ使用できます' end
    local m = run.members[src]
    if not m or m.role ~= 'mage' then return false, '魔導士のみ使用できます' end
    if m.downed then return false, '戦闘不能中です' end
    local skill = Config.Mage.skills[skillId]
    if not skill then return false, '不明なスキル' end
    local t = os.time()
    if (m.cooldowns[skillId] or 0) > t then return false, ('クールダウン中 (%d秒)'):format(m.cooldowns[skillId] - t) end
    if (m.mp or 0) < skill.mp then return false, 'MPが足りません' end
    local myPos = Instances.PedCoords(src)
    if not myPos then return false end

    local function inRange(s, range)
        local p = Instances.PedCoords(s)
        return p and #(p - myPos) <= range + 2.0
    end

    targetSrc = tonumber(targetSrc)
    local applied = false
    if skill.target == 'ally' then
        -- 対象未指定/無効時: ヒールは最もHP割合の低い味方、バフは近くのアタッカー優先
        local target = targetSrc and run.members[targetSrc]
        if not target or target.left or target.downed or not inRange(targetSrc, skill.range) then
            target, targetSrc = nil, nil
            local best
            for s, mm in pairs(run.members) do
                if not mm.left and not mm.downed and inRange(s, skill.range) and (skillId ~= 'buff' or mm.role ~= 'mage') then
                    local score
                    if skillId == 'heal' then score = Instances.RpgHp(s, mm) / mm.maxHp
                    else score = (mm.role == 'attacker' and 0 or 1) end
                    if not best or score < best then best, target, targetSrc = score, mm, s end
                end
            end
        end
        if not target then return false, '射程内に対象がいません' end
        if skillId == 'heal' then
            Combat.HealMember(run, targetSrc, skill.amountPct, src)
        elseif skillId == 'buff' then
            if target.role == 'mage' then return false, '魔導士には付与できません' end
            target.buff = { bonus = skill.damageBonus, expires = t + skill.duration }
            TriggerClientEvent('projectin_rpg:client:toast', targetSrc, { message = ('%s からパワーブーストを受けた！(%d秒)'):format(m.name, skill.duration), type = 'buff' })
        end
        Instances.SendRun(run, 'projectin_rpg:client:skillFx', { skill = skillId, from = src, to = targetSrc })
        applied = true
    elseif skill.target == 'area' then
        for s, mm in pairs(run.members) do
            if not mm.left and not mm.downed and inRange(s, skill.range) then
                Combat.HealMember(run, s, skill.amountPct, src)
                applied = true
            end
        end
        Instances.SendRun(run, 'projectin_rpg:client:skillFx', { skill = skillId, from = src })
        if not applied then return false, '範囲内に味方がいません' end
    elseif skill.target == 'downed' then
        local target = targetSrc and run.members[targetSrc]
        if not target or not target.downed or not inRange(targetSrc, skill.range) then
            target, targetSrc = nil, nil
            for s, mm in pairs(run.members) do
                if not mm.left and mm.downed and inRange(s, skill.range) then target, targetSrc = mm, s break end
            end
        end
        if not target then return false, '近くに戦闘不能の味方がいません' end
        applied = Combat.Revive(run, targetSrc, skill.hpPct)
        Instances.SendRun(run, 'projectin_rpg:client:skillFx', { skill = skillId, from = src, to = targetSrc })
    end
    if not applied then return false, '効果がありませんでした' end
    m.mp = m.mp - skill.mp
    m.cooldowns[skillId] = t + skill.cooldown
    Instances.PushParty(run)
    return true
end

---------------------------------------------------------------------------
-- 定期処理 (MP回復 / バフ失効 / ボス範囲攻撃)
---------------------------------------------------------------------------
function Combat.Tick(run, t)
    for _, m in pairs(run.members) do
        if not m.left and m.role == 'mage' and not m.downed then
            m.mp = math.min(Config.Mage.maxMp, (m.mp or 0) + Config.Mage.mpRegenPerSec * 0.5)
        end
        if m.buff and m.buff.expires <= t then m.buff = nil end
    end
    local b = run.boss
    if b and b.enemy and b.enemy.alive and b.nextAoeAt and t >= b.nextAoeAt then
        local ph = run.def.boss.phases[b.phase]
        local aoe = ph and ph.aoe
        if not aoe then b.nextAoeAt = nil return end
        b.nextAoeAt = t + aoe.interval
        local candidates = {}
        for s, m in pairs(run.members) do
            if not m.left and not m.downed then candidates[#candidates + 1] = s end
        end
        if #candidates == 0 then return end
        local targetPos = Instances.PedCoords(candidates[math.random(#candidates)])
        if not targetPos then return end
        local id = ('%s_%d'):format(run.id, GetGameTimer())
        Instances.SendRun(run, 'projectin_rpg:client:aoe', { id = id, x = targetPos.x, y = targetPos.y, z = targetPos.z, radius = aoe.radius, delay = aoe.delay })
        SetTimeout(math.floor(aoe.delay * 1000), function()
            if run.state ~= 'active' then return end
            local dmg = math.floor(aoe.damagePct * Config.Health.baseHp)
            for s, m in pairs(run.members) do
                if not m.left and not m.downed then
                    local p = Instances.PedCoords(s)
                    if p and #(vector2(p.x, p.y) - vector2(targetPos.x, targetPos.y)) <= aoe.radius and math.abs(p.z - targetPos.z) < 6.0 then
                        TriggerClientEvent('projectin_rpg:client:damage', s, dmg)
                    end
                end
            end
            Instances.SendRun(run, 'projectin_rpg:client:aoeBoom', { id = id })
        end)
    end
end
