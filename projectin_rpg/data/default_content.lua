--[[
    初期コンテンツ (初回起動時にDBへ投入されます。以降はゲーム内エディターで編集)
    座標はGTA標準マップの既存ロケーションです。
    ※ 実機で未検証の座標を含むため、Z座標はクライアント側で地面にスナップします。
      ずれている場合はエディターの「現在地を設定」「配置モード」で調整してください。
]]

DefaultContent = {}

local quarryEnemies = {
    grunt = {
        label = '採石場の荒くれ', model = 'g_m_y_lost_01', hp = 260, weapon = 'WEAPON_BAT', accuracy = 25, armor = 0,
        loot = { { item = 'iron_scrap', min = 1, max = 3, chance = 70 }, { item = 'potion_small', min = 1, max = 1, chance = 12 } },
    },
    gunner = {
        label = '荒くれガンナー', model = 'g_m_y_lost_02', hp = 220, weapon = 'WEAPON_PISTOL', accuracy = 18, armor = 0,
        loot = { { item = 'iron_scrap', min = 1, max = 2, chance = 60 }, { item = 'quartz_shard', min = 1, max = 1, chance = 20 } },
    },
    ghoul = {
        label = '結晶グール', model = 'u_m_y_zombie_01', hp = 320, weapon = 'WEAPON_UNARMED', accuracy = 40, armor = 0,
        loot = { { item = 'slime_gel', min = 1, max = 2, chance = 75 }, { item = 'quartz_shard', min = 1, max = 2, chance = 30 } },
    },
    goz = {
        label = '鉄腕のゴズ', model = 'g_m_m_chicold_01', hp = 4200, weapon = 'WEAPON_MACHETE', accuracy = 45, armor = 100,
        damageReduction = 0.1, isBoss = true,
        loot = { { item = 'cursed_crystal', min = 1, max = 2, chance = 100 }, { item = 'potion_large', min = 1, max = 1, chance = 40 } },
    },
}

DefaultContent.dungeon = {
    name = '採石場の魔窟',
    type = 'dungeon',
    description = 'デイビス・クォーツ採石場の地下から呪われた結晶が湧き出した。荒くれ者と結晶グールを退け、汚染コアを破壊せよ。',
    recommended = '1〜4人 / 初心者向け',
    minPlayers = 1, maxPlayers = 4, timeLimit = 1200,
    locationLabel = 'デイビス・クォーツ採石場',
    ipls = {},
    entry = { x = 2569.0, y = 2720.5, z = 42.9, h = 210.0 },
    start = { x = 2953.0, y = 2786.0, z = 41.5, h = 300.0 },
    exit  = { x = 2569.0, y = 2720.5, z = 42.9, h = 210.0 },
    boundary = { center = { x = 2955.0, y = 2790.0, z = 41.5 }, radius = 75.0, height = 60.0 },
    enemies = quarryEnemies,
    spawnPoints = {
        { id = 'n1', label = '北の斜面', x = 2965.0, y = 2820.0, z = 43.0, h = 180.0 },
        { id = 'e1', label = '東の重機', x = 2990.0, y = 2790.0, z = 41.0, h = 90.0 },
        { id = 's1', label = '南の資材置き場', x = 2950.0, y = 2755.0, z = 42.0, h = 0.0 },
        { id = 'w1', label = '西の坑道口', x = 2920.0, y = 2795.0, z = 42.0, h = 270.0 },
        { id = 'boss', label = 'ボス出現地点', x = 2972.0, y = 2800.0, z = 41.0, h = 230.0 },
    },
    props = {
        { id = 'core_a', label = '汚染コアA', model = 'prop_rad_waste_barrel_01', x = 2962.0, y = 2808.0, z = 41.0, h = 0.0 },
        { id = 'core_b', label = '汚染コアB', model = 'prop_rad_waste_barrel_01', x = 2978.0, y = 2778.0, z = 41.0, h = 0.0 },
        { id = 'core_c', label = '汚染コアC', model = 'prop_rad_waste_barrel_01', x = 2938.0, y = 2772.0, z = 41.0, h = 0.0 },
        { id = 'light1', label = '照明', model = 'prop_worklight_03b', x = 2955.0, y = 2792.0, z = 41.0, h = 45.0 },
        { id = 'barrier1', label = 'バリケード', model = 'prop_barrier_work05', x = 2945.0, y = 2782.0, z = 41.0, h = 90.0 },
    },
    waves = {
        {
            label = '第1ウェーブ: 侵入者', message = '採石場を占拠する荒くれ者を一掃せよ！', delay = 5,
            objective = { type = 'kill_all' },
            groups = {
                { enemy = 'grunt', count = 4, spawn = { 'n1', 'e1' } },
                { enemy = 'gunner', count = 2, spawn = { 's1' } },
            },
        },
        {
            label = '第2ウェーブ: 汚染コア', message = '3つの汚染コアを破壊せよ！(近づいて長押し)', delay = 4,
            objective = { type = 'interact', targets = { 'core_a', 'core_b', 'core_c' }, interactTime = 4, label = '汚染コアを破壊' },
            groups = {
                { enemy = 'ghoul', count = 5, spawn = { 'n1', 'w1', 'e1' } },
            },
        },
        {
            label = '第3ウェーブ: 結晶の奔流', message = 'グールの群れが押し寄せる！60秒耐え抜け！', delay = 4,
            objective = { type = 'survive', duration = 60 },
            groups = {
                { enemy = 'ghoul', count = 4, spawn = { 'n1', 'e1', 's1', 'w1' }, respawn = true },
            },
        },
        {
            label = '最終ウェーブ: 鉄腕のゴズ', message = '採石場の主が姿を現した！', delay = 5,
            objective = { type = 'boss' },
            groups = {},
        },
    },
    boss = {
        enemy = 'goz', spawn = 'boss',
        phases = {
            { hpPct = 100, label = '第1形態', message = 'ゴズ「ここは俺の縄張りだ！」', damageTakenMult = 1.0,
              aoe = { interval = 14, radius = 5, delay = 2.5, damagePct = 0.25 } },
            { hpPct = 50, label = '激昂', message = 'ゴズが手下を呼び寄せた！', damageTakenMult = 0.8, accuracy = 60,
              aoe = { interval = 10, radius = 6, delay = 2.0, damagePct = 0.3 },
              adds = { enemy = 'grunt', count = 3, spawn = { 'n1', 'w1' } } },
        },
    },
    rewards = {
        clear = {
            { item = 'dungeon_token', min = 3, max = 5, chance = 100 },
            { item = 'quartz_shard', min = 2, max = 4, chance = 100 },
            { item = 'cursed_crystal', min = 1, max = 1, chance = 35 },
            { item = 'potion_small', min = 1, max = 2, chance = 60 },
        },
    },
    announcements = {},
}

local raidEnemies = {
    soldier = {
        label = '山頂の傭兵', model = 's_m_y_blackops_01', hp = 420, weapon = 'WEAPON_CARBINERIFLE', accuracy = 15, armor = 50,
        loot = { { item = 'iron_scrap', min = 2, max = 4, chance = 70 }, { item = 'potion_small', min = 1, max = 1, chance = 20 } },
    },
    brute = {
        label = '重装の傭兵', model = 's_m_y_blackops_02', hp = 900, weapon = 'WEAPON_PUMPSHOTGUN', accuracy = 20, armor = 100,
        damageReduction = 0.15,
        loot = { { item = 'beast_fang', min = 1, max = 1, chance = 25 }, { item = 'ether', min = 1, max = 1, chance = 20 } },
    },
    titan = {
        label = 'タイタン・ジャガーノート', model = 'u_m_y_juggernaut_01', hp = 38000, weapon = 'WEAPON_COMBATMG', accuracy = 12, armor = 100,
        damageReduction = 0.2, isBoss = true,
        loot = { { item = 'beast_fang', min = 1, max = 3, chance = 100 } },
    },
}

DefaultContent.raid = {
    name = 'チリアド山頂決戦',
    type = 'raid',
    description = 'チリアド山頂に装甲巨兵「タイタン・ジャガーノート」が降り立った。最大12人で討伐せよ。',
    recommended = '6〜12人 / 上級者向け',
    minPlayers = 1, maxPlayers = 12, timeLimit = 1800,
    locationLabel = 'チリアド山 山頂',
    ipls = {},
    entry = { x = 446.3, y = 5568.6, z = 781.2, h = 90.0 },
    start = { x = 495.0, y = 5590.0, z = 795.0, h = 30.0 },
    exit  = { x = 446.3, y = 5568.6, z = 781.2, h = 90.0 },
    boundary = { center = { x = 501.0, y = 5600.0, z = 795.0 }, radius = 70.0, height = 60.0 },
    enemies = raidEnemies,
    spawnPoints = {
        { id = 'ridge_n', label = '北の尾根', x = 505.0, y = 5630.0, z = 790.0, h = 180.0 },
        { id = 'ridge_e', label = '東の崖', x = 530.0, y = 5600.0, z = 790.0, h = 90.0 },
        { id = 'ridge_w', label = '西の展望台', x = 475.0, y = 5610.0, z = 792.0, h = 270.0 },
        { id = 'summit', label = '山頂', x = 501.8, y = 5604.5, z = 797.9, h = 200.0 },
    },
    props = {
        { id = 'tent', label = '前線テント', model = 'prop_gazebo_02', x = 490.0, y = 5588.0, z = 795.0, h = 30.0 },
        { id = 'light', label = '投光器', model = 'prop_worklight_03b', x = 498.0, y = 5596.0, z = 796.0, h = 200.0 },
    },
    waves = {
        {
            label = '前哨戦: 傭兵部隊', message = '山頂を守る傭兵部隊を突破せよ！', delay = 8,
            objective = { type = 'kill_all' },
            groups = {
                { enemy = 'soldier', count = 8, spawn = { 'ridge_n', 'ridge_e', 'ridge_w' } },
                { enemy = 'brute', count = 2, spawn = { 'summit' } },
            },
        },
        {
            label = '決戦: タイタン・ジャガーノート', message = '大地を揺るがす足音…巨兵が現れた！', delay = 8,
            objective = { type = 'boss' },
            groups = {},
        },
    },
    boss = {
        enemy = 'titan', spawn = 'summit',
        phases = {
            { hpPct = 100, label = '起動', message = 'タイタンが起動した！赤い円から離れろ！', damageTakenMult = 1.0,
              aoe = { interval = 14, radius = 6, delay = 3.0, damagePct = 0.3 } },
            { hpPct = 70, label = '増援要請', message = 'タイタンが増援を呼んだ！', damageTakenMult = 0.9,
              aoe = { interval = 11, radius = 7, delay = 2.5, damagePct = 0.3 },
              adds = { enemy = 'soldier', count = 6, spawn = { 'ridge_n', 'ridge_e', 'ridge_w' } } },
            { hpPct = 40, label = '装甲展開', message = '装甲が強化された！タンクは前へ！', damageTakenMult = 0.7,
              aoe = { interval = 9, radius = 8, delay = 2.5, damagePct = 0.35 },
              adds = { enemy = 'brute', count = 2, spawn = { 'ridge_e', 'ridge_w' } } },
            { hpPct = 15, label = '暴走', message = 'タイタンが暴走している！一気に畳みかけろ！', damageTakenMult = 1.2, accuracy = 35,
              aoe = { interval = 6, radius = 7, delay = 2.0, damagePct = 0.4 } },
        },
    },
    rewards = {
        clear = {
            { item = 'raid_token', min = 5, max = 8, chance = 100 },
            { item = 'titan_core', min = 1, max = 1, chance = 100 },
            { item = 'beast_fang', min = 1, max = 2, chance = 60 },
            { item = 'potion_large', min = 1, max = 2, chance = 60 },
            { item = 'summit_crown', min = 1, max = 1, chance = 5 },
        },
    },
    announcements = {},
}

-- 再利用テンプレート
DefaultContent.templates = {
    { kind = 'definition', name = '基本ダンジョン(4ウェーブ+ボス)', data = DefaultContent.dungeon },
    { kind = 'definition', name = '基本レイド(前哨戦+4フェーズボス)', data = DefaultContent.raid },
    { kind = 'enemy', name = '近接ザコ(バット)', data = quarryEnemies.grunt },
    { kind = 'enemy', name = '遠距離ザコ(ピストル)', data = quarryEnemies.gunner },
    { kind = 'enemy', name = 'ゾンビ(素手)', data = quarryEnemies.ghoul },
    { kind = 'enemy', name = '傭兵(ライフル)', data = raidEnemies.soldier },
    { kind = 'enemy', name = '重装兵(ショットガン)', data = raidEnemies.brute },
    { kind = 'enemy', name = '大型ボス(ジャガーノート)', data = raidEnemies.titan },
}
