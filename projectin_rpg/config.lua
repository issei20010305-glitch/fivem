--[[
    projectin_rpg 設定ファイル
    ここの値はサーバー/クライアント共通で読み込まれます。
    ダンジョン・レイドの内容(敵・ウェーブ・報酬など)はゲーム内エディターで編集し、DBに保存されます。
]]

Config = {}

Config.Debug = false

-- 日本時間 (JST = UTC+9, 夏時間なし)
Config.TimezoneOffset = 9 * 3600
Config.TimezoneLabel = 'JST'

-------------------------------------------------------------------------------
-- 管理者権限 (いずれか1つを満たせば管理者)
-- 1) ACE: server.cfg 例
--      add_ace group.admin projectin_rpg.admin allow
-- 2) Qbox の権限: exports.qbx_core:HasPermission(src, 'admin') など
-- 3) 識別子の直接指定 (ACEが効かない環境向け)
-- うまく行かない場合はゲーム内で /rpgperm を実行すると判定結果が表示されます。
-------------------------------------------------------------------------------
Config.AdminAces = { 'projectin_rpg.admin', 'group.admin', 'group.god', 'admin', 'god' }
Config.AdminQbxPermissions = { 'admin', 'god' }
Config.AdminIdentifiers = {
    -- 'fivem:14668373',
    -- 'discord:730697978083409922',
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
}

-------------------------------------------------------------------------------
-- ロール
-- 効果はアクティブなダンジョン/レイド内でのみ適用されます。
-------------------------------------------------------------------------------
Config.Roles = {
    tank = {
        label = 'タンク',
        description = '高い耐久力で仲間を守る盾。HP1.5倍 / 与ダメージ0.8倍。',
        hpMult = 1.5, damageMult = 0.8, canAttack = true, inventoryMult = 1.0,
        color = '#4aa3ff', icon = '🛡',
        loadout = {
            { item = 'WEAPON_BAT', count = 1 },
            { item = 'WEAPON_PISTOL', count = 1 },
            { item = 'ammo-9', count = 200 },
        },
    },
    attacker = {
        label = 'アタッカー',
        description = '圧倒的な火力で敵を殲滅。HP0.8倍 / 与ダメージ1.5倍。',
        hpMult = 0.8, damageMult = 1.5, canAttack = true, inventoryMult = 1.0,
        color = '#ff5a5a', icon = '⚔',
        loadout = {
            { item = 'WEAPON_SMG', count = 1 },
            { item = 'WEAPON_PISTOL', count = 1 },
            { item = 'ammo-9', count = 400 },
        },
    },
    porter = {
        label = '荷物持ち',
        description = '戦利品を大量に持ち帰る運び屋。RPGインベントリのスロット数・重量上限が2倍。',
        hpMult = 1.0, damageMult = 1.0, canAttack = true, inventoryMult = 2.0,
        color = '#ffc24a', icon = '🎒',
        loadout = {
            { item = 'WEAPON_PISTOL', count = 1 },
            { item = 'ammo-9', count = 200 },
        },
    },
    mage = {
        label = '魔導士',
        description = 'MPを使い仲間を回復・強化する支援職。攻撃はできません。',
        hpMult = 1.0, damageMult = 0.0, canAttack = false, inventoryMult = 1.0,
        color = '#b57bff', icon = '✦',
        loadout = {},
    },
}
Config.RoleOrder = { 'tank', 'attacker', 'porter', 'mage' }

-- 魔導士スキル (サーバー側でMP/クールダウン/射程/対象を検証)
Config.Mage = {
    maxMp = 100,
    mpRegenPerSec = 2.0,
    skills = {
        heal     = { key = 1, label = 'ヒール',       mp = 25, cooldown = 6,  range = 30.0, amountPct = 0.35, target = 'ally' },
        buff     = { key = 2, label = 'パワーブースト', mp = 35, cooldown = 18, range = 30.0, damageBonus = 0.35, duration = 15, target = 'ally' },
        areaHeal = { key = 3, label = 'サンクチュアリ', mp = 55, cooldown = 30, range = 15.0, amountPct = 0.25, target = 'area' },
        revive   = { key = 4, label = 'リザレクション', mp = 70, cooldown = 45, range = 6.0,  hpPct = 0.4, target = 'downed' },
    },
}

-------------------------------------------------------------------------------
-- プレイヤー体力 (ダンジョン内のみ)
-- GTAのプレイヤー体力は 100 = 死亡ライン。基準HPは100(=ネイティブ200)。
-------------------------------------------------------------------------------
Config.Health = {
    baseHp = 100,          -- RPG上の基準HP
    nativeScale = 1.0,     -- RPG HP1 あたりのネイティブ体力
    downedBuffer = 30,     -- ネイティブ死亡前にダウン扱いにする余裕(ネイティブ値)
    downedAutoReviveOnWaveClear = true,
    waveClearRevivePct = 0.3,
}

-------------------------------------------------------------------------------
-- 戦闘 (サーバー権威ダメージ)
-- 武器ごとの基礎ダメージ / 最短発射間隔(ms) / 最大射程(m)
-------------------------------------------------------------------------------
Config.Weapons = {
    WEAPON_UNARMED       = { damage = 6,  interval = 400, range = 3.0 },
    WEAPON_BAT           = { damage = 28, interval = 550, range = 4.0 },
    WEAPON_PISTOL        = { damage = 22, interval = 180, range = 60.0 },
    WEAPON_SMG           = { damage = 14, interval = 70,  range = 55.0 },
    WEAPON_CARBINERIFLE  = { damage = 20, interval = 100, range = 90.0 },
    WEAPON_PUMPSHOTGUN   = { damage = 70, interval = 750, range = 25.0 },
}
Config.HeadshotMult = 1.3
Config.MaxHitDistancePadding = 6.0

-------------------------------------------------------------------------------
-- RPGインベントリ (通常のox_inventoryとは完全に別管理)
-------------------------------------------------------------------------------
Config.RpgInventory = {
    baseSlots = 30,
    baseWeight = 60000, -- g
}

-------------------------------------------------------------------------------
-- 通常インベントリの預かり (入場時にox_inventoryの所持品を専用スタッシュへ退避)
-------------------------------------------------------------------------------
Config.Holding = {
    enabled = true,
    stashPrefix = 'rpghold_',
    stashSlots = 200,
    stashWeight = 100000000,
    keepItems = {},          -- 例: { 'phone', 'radio' } 退避しないアイテム
    loanerMetaKey = 'rpgLoaner',
}

-------------------------------------------------------------------------------
-- パーティー
-------------------------------------------------------------------------------
Config.Party = {
    maxSize = 4,
    inviteTimeout = 60,
    entryRange = 15.0,       -- 入口から何m以内のメンバーが入場できるか
}

-------------------------------------------------------------------------------
-- インスタンス
-------------------------------------------------------------------------------
Config.Instance = {
    bucketStart = 7000,       -- ルーティングバケット開始番号 (他リソースと被らないように)
    bucketMax = 7999,
    lockdownMode = 'relaxed', -- 'strict' でクライアント生成エンティティを禁止
    maxAliveEnemies = 40,
    boundaryGrace = 6,        -- 境界外にいられる秒数
    resultsAutoLeave = 45,    -- 結果画面から自動帰還するまでの秒数
    hpReportInterval = 1000,
    lootPickupRange = 2.5,
    interactRange = 3.0,
    unclaimedLootOnClear = 'auto', -- 'auto' = クリア時に未回収の個人ドロップを自動回収
}

-------------------------------------------------------------------------------
-- 医療リソース連携 (ダンジョン内で万一ネイティブ死亡した場合の蘇生)
-- 使用中の医療スクリプトのクライアント蘇生イベントを指定してください。
-------------------------------------------------------------------------------
Config.Medical = {
    reviveClientEvent = 'qbx_medical:client:playerRevived', -- 不要なら false
}

-------------------------------------------------------------------------------
-- イベントスケジューラー
-------------------------------------------------------------------------------
Config.Events = {
    tickSeconds = 15,
    raidReminderMinutes = { 30, 10, 5, 1 },
    dungeonReminderMinutes = { 60 },  -- 終了の何分前に告知するか
    raidLobbyRange = 40.0,
}

-- 告知テンプレート (エディターで個別に上書き可能)
-- {location} {name} {end} {startIn} {start}
Config.DefaultAnnouncements = {
    dungeon_open = '{location}でダンジョン発生！{end}まで！',
    dungeon_reminder = '{location}のダンジョンは{end}で消滅します！',
    raid_announce = '{location}で大型ボスレイド発生！開始まで{startIn}！',
    raid_reminder = '{location}の大型ボスレイド開始まで{startIn}！',
    raid_start = '{location}の大型ボスレイドが開始されました！',
}

-------------------------------------------------------------------------------
-- キー
-------------------------------------------------------------------------------
Config.Keys = {
    interact = 'E',
    skill1 = '1', skill2 = '2', skill3 = '3', skill4 = '4',
    target = 'G',
}

-- エディター上限 (サーバー側で強制)
Config.EditorLimits = {
    maxWaves = 15,
    maxGroupsPerWave = 8,
    maxEnemiesPerGroup = 20,
    maxSpawnPoints = 40,
    maxProps = 40,
    maxPhases = 6,
    maxRewards = 20,
    maxEnemyHp = 200000,
    maxNameLength = 48,
    maxTextLength = 300,
}
