--[[
    ダンジョン/レイド定義のスキーマとサニタイズ
    エディターから送られた定義はサーバーで必ず Sanitize() を通し、
    既知のフィールドのみを型・範囲チェックして再構築します。
]]

RPG = RPG or {}
local U = RPG.Utils
local S = {}
RPG.Schema = S

local L = Config.EditorLimits

S.ObjectiveTypes = {
    kill_all = '敵を全滅させる',
    kill_count = '指定数の敵を倒す',
    interact = '対象を破壊/起動する',
    survive = '一定時間生き残る',
    boss = 'ボスを討伐する',
}

S.Weapons = {
    'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_BAT', 'WEAPON_MACHETE', 'WEAPON_PISTOL',
    'WEAPON_COMBATPISTOL', 'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_ASSAULTRIFLE',
    'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_MG', 'WEAPON_COMBATMG',
}
local weaponSet = {}
for _, w in ipairs(S.Weapons) do weaponSet[w] = true end

local function str(v, max, default)
    if type(v) ~= 'string' then return default or '' end
    v = v:gsub('[%c]', ' ')
    if #v > (max or L.maxTextLength) then v = v:sub(1, max or L.maxTextLength) end
    return v
end

local function ident(v, default)
    if type(v) ~= 'string' then return default end
    v = v:gsub('[^%w_%-]', '')
    if v == '' then return default end
    return v:sub(1, 32)
end

local function num(v, lo, hi, default)
    local n = tonumber(v)
    if not n or n ~= n then return default end
    return U.clamp(n, lo, hi)
end

local function int(v, lo, hi, default)
    local n = num(v, lo, hi, default)
    return n and math.floor(n) or n
end

local function coord(v, withHeading)
    if type(v) ~= 'table' then return nil end
    local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
    if not x or not y or not z then return nil end
    if math.abs(x) > 20000 or math.abs(y) > 20000 or z < -500 or z > 3000 then return nil end
    local c = { x = U.round(x, 3), y = U.round(y, 3), z = U.round(z, 3) }
    if withHeading then c.h = U.round(num(v.h, -720, 720, 0.0), 2) end
    return c
end

local function model(v)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('[^%w_]', '')
    if v == '' or #v > 48 then return nil end
    return v
end

local function lootList(list, max)
    local out = {}
    if type(list) ~= 'table' then return out end
    for _, r in ipairs(list) do
        if #out >= (max or L.maxRewards) then break end
        if type(r) == 'table' and type(r.item) == 'string' and RPG.Items[r.item] then
            local mn = int(r.min, 1, 999, 1)
            local mx = int(r.max, mn, 999, mn)
            out[#out + 1] = { item = r.item, min = mn, max = mx, chance = num(r.chance, 0, 100, 100) }
        end
    end
    return out
end

function S.SanitizeEnemy(e)
    if type(e) ~= 'table' then return nil end
    local m = model(e.model)
    if not m then return nil end
    local weapon = (type(e.weapon) == 'string' and weaponSet[e.weapon]) and e.weapon or 'WEAPON_UNARMED'
    return {
        label = str(e.label, L.maxNameLength, '敵'),
        model = m,
        hp = int(e.hp, 1, L.maxEnemyHp, 100),
        weapon = weapon,
        accuracy = int(e.accuracy, 0, 100, 30),
        armor = int(e.armor, 0, 100, 0),
        damageReduction = num(e.damageReduction, 0, 0.9, 0),
        isBoss = e.isBoss == true,
        loot = lootList(e.loot, 10),
    }
end

local function objective(o, propIds)
    o = type(o) == 'table' and o or {}
    local t = S.ObjectiveTypes[o.type] and o.type or 'kill_all'
    local out = { type = t }
    if t == 'kill_count' then out.count = int(o.count, 1, 500, 10) end
    if t == 'survive' then out.duration = int(o.duration, 10, 1800, 60) end
    if t == 'interact' then
        out.targets = {}
        for _, id in ipairs(type(o.targets) == 'table' and o.targets or {}) do
            id = ident(id)
            if id and propIds[id] then out.targets[#out.targets + 1] = id end
        end
        out.interactTime = num(o.interactTime, 1, 30, 4)
        out.label = str(o.label, L.maxNameLength, '結晶を破壊')
    end
    return out
end

function S.Sanitize(d)
    if type(d) ~= 'table' then return nil, '定義データが不正です' end
    local out = {}
    out.name = str(d.name, L.maxNameLength, '')
    if out.name == '' then return nil, '名前を入力してください' end
    out.type = (d.type == 'raid') and 'raid' or 'dungeon'
    out.description = str(d.description, L.maxTextLength, '')
    out.recommended = str(d.recommended, L.maxNameLength, '')
    local maxCap = out.type == 'raid' and 24 or Config.Party.maxSize
    out.maxPlayers = int(d.maxPlayers, 1, maxCap, out.type == 'raid' and 12 or 4)
    out.minPlayers = int(d.minPlayers, 1, out.maxPlayers, 1)
    out.timeLimit = int(d.timeLimit, 60, 7200, out.type == 'raid' and 1800 or 1200)
    out.locationLabel = str(d.locationLabel, L.maxNameLength, '')

    out.ipls = {}
    for _, ipl in ipairs(type(d.ipls) == 'table' and d.ipls or {}) do
        if type(ipl) == 'string' and #out.ipls < 20 then
            local v = ipl:gsub('[^%w_%-]', '')
            if v ~= '' then out.ipls[#out.ipls + 1] = v:sub(1, 64) end
        end
    end

    out.entry = coord(d.entry, true)
    out.start = coord(d.start, true)
    out.exit = coord(d.exit, true)
    if not out.entry then return nil, '入口(街側)の座標を設定してください' end
    if not out.start then return nil, '開始地点の座標を設定してください' end

    local b = type(d.boundary) == 'table' and d.boundary or {}
    out.boundary = {
        center = coord(b.center) or { x = out.start.x, y = out.start.y, z = out.start.z },
        radius = num(b.radius, 10, 600, 80),
        height = num(b.height, 5, 500, 60),
    }

    -- 敵プリセット
    out.enemies = {}
    local enemyCount = 0
    for key, e in pairs(type(d.enemies) == 'table' and d.enemies or {}) do
        local k = ident(key)
        local se = k and S.SanitizeEnemy(e)
        if se and enemyCount < 30 then
            out.enemies[k] = se
            enemyCount = enemyCount + 1
        end
    end
    if enemyCount == 0 then return nil, '敵プリセットを1つ以上作成してください' end

    -- スポーン地点
    out.spawnPoints = {}
    local spIds = {}
    for _, sp in ipairs(type(d.spawnPoints) == 'table' and d.spawnPoints or {}) do
        if #out.spawnPoints >= L.maxSpawnPoints then break end
        local c = coord(sp, true)
        local id = ident(sp.id)
        if c and id and not spIds[id] then
            c.id = id
            c.label = str(sp.label, L.maxNameLength, id)
            out.spawnPoints[#out.spawnPoints + 1] = c
            spIds[id] = true
        end
    end
    if #out.spawnPoints == 0 then return nil, 'スポーン地点を1つ以上配置してください' end

    -- プロップ
    out.props = {}
    local propIds = {}
    for _, p in ipairs(type(d.props) == 'table' and d.props or {}) do
        if #out.props >= L.maxProps then break end
        local c = coord(p, true)
        local m = model(p.model)
        local id = ident(p.id)
        if c and m and id and not propIds[id] then
            c.id = id
            c.model = m
            c.label = str(p.label, L.maxNameLength, id)
            out.props[#out.props + 1] = c
            propIds[id] = true
        end
    end

    -- ボス
    if type(d.boss) == 'table' and d.boss.enemy then
        local bk = ident(d.boss.enemy)
        if bk and out.enemies[bk] then
            local boss = { enemy = bk, spawn = spIds[ident(d.boss.spawn) or ''] and ident(d.boss.spawn) or out.spawnPoints[1].id, phases = {} }
            for _, ph in ipairs(type(d.boss.phases) == 'table' and d.boss.phases or {}) do
                if #boss.phases >= L.maxPhases then break end
                if type(ph) == 'table' then
                    local phase = {
                        hpPct = int(ph.hpPct, 1, 100, 100),
                        label = str(ph.label, L.maxNameLength, 'フェーズ'),
                        message = str(ph.message, L.maxTextLength, ''),
                        damageTakenMult = num(ph.damageTakenMult, 0.1, 3, 1),
                        accuracy = ph.accuracy ~= nil and int(ph.accuracy, 0, 100, nil) or nil,
                    }
                    if type(ph.aoe) == 'table' and ph.aoe.enabled ~= false then
                        phase.aoe = {
                            interval = num(ph.aoe.interval, 4, 120, 12),
                            radius = num(ph.aoe.radius, 2, 30, 6),
                            delay = num(ph.aoe.delay, 1, 10, 2.5),
                            damagePct = num(ph.aoe.damagePct, 0.05, 1.0, 0.3),
                        }
                    end
                    if type(ph.adds) == 'table' and ph.adds.enemy then
                        local ak = ident(ph.adds.enemy)
                        if ak and out.enemies[ak] then
                            local spawns = {}
                            for _, s in ipairs(type(ph.adds.spawn) == 'table' and ph.adds.spawn or {}) do
                                local sid = ident(s)
                                if sid and spIds[sid] then spawns[#spawns + 1] = sid end
                            end
                            if #spawns == 0 then spawns = { out.spawnPoints[1].id } end
                            phase.adds = { enemy = ak, count = int(ph.adds.count, 1, L.maxEnemiesPerGroup, 3), spawn = spawns }
                        end
                    end
                    boss.phases[#boss.phases + 1] = phase
                end
            end
            table.sort(boss.phases, function(a, b) return a.hpPct > b.hpPct end)
            if #boss.phases == 0 then boss.phases = { { hpPct = 100, label = '第1形態', message = '', damageTakenMult = 1 } } end
            out.boss = boss
        end
    end

    -- ウェーブ
    out.waves = {}
    for _, w in ipairs(type(d.waves) == 'table' and d.waves or {}) do
        if #out.waves >= L.maxWaves then break end
        if type(w) == 'table' then
            local wave = {
                label = str(w.label, L.maxNameLength, ('ウェーブ%d'):format(#out.waves + 1)),
                message = str(w.message, L.maxTextLength, ''),
                delay = num(w.delay, 0, 60, 3),
                objective = objective(w.objective, propIds),
                groups = {},
            }
            for _, g in ipairs(type(w.groups) == 'table' and w.groups or {}) do
                if #wave.groups >= L.maxGroupsPerWave then break end
                local ek = type(g) == 'table' and ident(g.enemy)
                if ek and out.enemies[ek] then
                    local spawns = {}
                    for _, s in ipairs(type(g.spawn) == 'table' and g.spawn or {}) do
                        local sid = ident(s)
                        if sid and spIds[sid] then spawns[#spawns + 1] = sid end
                    end
                    if #spawns == 0 then spawns = { out.spawnPoints[1].id } end
                    wave.groups[#wave.groups + 1] = {
                        enemy = ek,
                        count = int(g.count, 1, L.maxEnemiesPerGroup, 3),
                        spawn = spawns,
                        respawn = g.respawn == true, -- survive 用: 倒されると再出現
                    }
                end
            end
            if wave.objective.type == 'boss' and not out.boss then
                return nil, ('%s: ボス目標ですがボスが設定されていません'):format(wave.label)
            end
            if wave.objective.type == 'interact' and #wave.objective.targets == 0 then
                return nil, ('%s: 破壊対象のプロップを選択してください'):format(wave.label)
            end
            if (wave.objective.type == 'kill_all' or wave.objective.type == 'kill_count') and #wave.groups == 0 then
                return nil, ('%s: 敵グループを追加してください'):format(wave.label)
            end
            out.waves[#out.waves + 1] = wave
        end
    end
    if #out.waves == 0 then return nil, 'ウェーブを1つ以上作成してください' end

    out.rewards = { clear = lootList(type(d.rewards) == 'table' and d.rewards.clear, L.maxRewards) }

    out.announcements = {}
    for k, def in pairs(Config.DefaultAnnouncements) do
        local v = type(d.announcements) == 'table' and d.announcements[k]
        out.announcements[k] = (type(v) == 'string' and v ~= '') and str(v, 160) or def
    end

    return out
end

-- 簡易サマリ (一覧表示用)
function S.Summary(d)
    if type(d) ~= 'table' then return {} end
    local enemyTotal = 0
    for _, w in ipairs(d.waves or {}) do
        for _, g in ipairs(w.groups or {}) do enemyTotal = enemyTotal + (g.count or 0) end
    end
    return {
        waves = #(d.waves or {}),
        enemies = enemyTotal,
        hasBoss = d.boss ~= nil,
        maxPlayers = d.maxPlayers,
        timeLimit = d.timeLimit,
    }
end
