Config = {}

-- Prints extra information and draws ox_target debug zones.
Config.Debug = false

---------------------------------------------------------------------------
-- Commands & permissions
---------------------------------------------------------------------------
Config.Commands = {
    create  = 'createheist',   -- opens the Heist Creator (admin)
    setxp   = 'setheistxp',    -- /setheistxp [playerId] [amount] (admin)
    cancel  = 'cancelheist',   -- leader: cancels the heist / member: leaves the heist
    accept  = 'heistaccept',   -- accepts the latest party invite
    decline = 'heistdecline',  -- declines the latest party invite
}

-- ACE principals allowed to use the admin commands and every creator action.
-- Every admin action is re-checked on the server.
Config.AdminGroups = { 'group.admin' }

---------------------------------------------------------------------------
-- Police
---------------------------------------------------------------------------
Config.Police = {
    jobs          = { 'police', 'sheriff' }, -- job names that count as police
    requireOnDuty = true,                    -- only count on-duty officers
    cacheSeconds  = 5,                       -- how long the police count is cached
}

-- Police alert. WHEN and WHERE a heist alerts the police is set per heist in
-- the creator (警察への通報 tab). This block decides HOW the alert is delivered.
Config.PoliceAlert = {
    enabled = true,
    -- 'auto'        = ps-dispatch when it is running, otherwise the built-in alert
    -- 'ps-dispatch' = always ps-dispatch
    -- 'builtin'     = notification + map blip from this resource
    system = 'auto',

    -- ps-dispatch settings
    dispatch = {
        jobs     = { 'leo' }, -- job types that receive the call
        codeName = 'heist_creator',
        icon     = 'fas fa-mask',
        priority = 1,         -- 1 = red
        sprite   = 161,
        colour   = 1,
        scale    = 1.2,
        length   = 3,         -- minutes the call stays on the map
        radius   = 0,
        flash    = true,
    },

    -- built-in alert settings
    blipSeconds  = 90,
    blipSprite   = 161,
    blipColour   = 1,

    -- Optional server-side hook for another dispatch resource.
    -- Return true to skip everything above.
    ---@param coords vector3
    ---@param heistName string
    ---@param alert { title: string, code: string }
    custom = function(coords, heistName, alert)
        return false
    end,
}

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
Config.Database = {
    autoInstall = true, -- create the tables automatically when the resource starts
}

---------------------------------------------------------------------------
-- Heist HUD NPC
-- NPCs can be added / moved in-game from the creator ("HUD NPC" page).
-- The list below is only used until an admin saves NPCs in-game.
---------------------------------------------------------------------------
Config.Npc = {
    defaultModel   = 'g_m_m_chigoon_02',
    scenario       = 'WORLD_HUMAN_SMOKING',
    spawnDistance  = 60.0,
    targetDistance = 2.5,
    blip = {
        enabled = true,
        sprite  = 303,
        colour  = 46,
        scale   = 0.8,
        label   = 'ヘイスト',
    },
    defaults = {
        { model = 'g_m_m_chigoon_02', x = 215.76, y = -810.12, z = 30.73, w = 250.0 },
    },
}

---------------------------------------------------------------------------
-- Starting a heist
---------------------------------------------------------------------------
Config.Start = {
    npcDistance   = 15.0, -- the leader must be this close to a HUD NPC to start a heist
    travelTimeout = 20,   -- minutes the crew has to reach the starting point (0 = unlimited)
}

---------------------------------------------------------------------------
-- Heist XP
---------------------------------------------------------------------------
Config.XP = {
    -- XP bonus by number of participating players. The highest entry is used for bigger crews.
    partyBonus = {
        [1] = 0.00,
        [2] = 0.10,
        [3] = 0.20,
        [4] = 0.30,
    },
    -- false: only the party leader needs the required XP / true: every member needs it
    requireAllMembers = false,
    -- Members further away than this from the heist NPC when the heist is handed
    -- in do not count as participants (no XP). 0 = no distance check.
    participationDistance = 150.0,
    -- Rank titles shown in the Heist HUD (display only).
    ranks = {
        { xp = 0,     label = 'ルーキー' },
        { xp = 500,   label = 'チンピラ' },
        { xp = 1500,  label = 'プロ' },
        { xp = 4000,  label = 'ベテラン' },
        { xp = 8000,  label = 'エキスパート' },
        { xp = 15000, label = 'マスターマインド' },
    },
}

---------------------------------------------------------------------------
-- Cooldowns (the durations themselves are set per heist in the creator)
---------------------------------------------------------------------------
-- The server-wide cooldown ALWAYS starts the moment a heist is started.
-- The personal cooldown starts when the heist ends, or when a player leaves it.
Config.Cooldowns = {
    -- Also give the personal cooldown when the heist failed / was cancelled.
    applyOnFail = true,
}

---------------------------------------------------------------------------
-- Heist area (radius set per heist in the creator, 0 = no area)
-- Until the crew has finished every stage and looted at least one point, the
-- heist fails when the crew leaves the area.
---------------------------------------------------------------------------
Config.Area = {
    -- 'all' = fails when EVERY member is outside / 'any' = fails when ONE member is outside
    mode         = 'all',
    graceSeconds = 10,   -- time to get back inside before the heist fails
    showOnMap    = true, -- draw the area on the map while it is active
}

---------------------------------------------------------------------------
-- Party
---------------------------------------------------------------------------
Config.Party = {
    maxSize        = 4,    -- maximum party size (a heist can restrict this further)
    inviteTimeout  = 60,   -- seconds before an invite expires
    nearbyDistance = 15.0, -- radius used for the "nearby players" list
}

---------------------------------------------------------------------------
-- Interactions
---------------------------------------------------------------------------
Config.Interaction = {
    key            = 38,   -- control index for "Press E" interactions
    keyLabel       = 'E',
    distance       = 1.6,  -- Press E distance
    targetRadius   = 1.0,  -- ox_target sphere radius
    targetDistance = 2.0,  -- ox_target interaction distance
    markerDistance = 25.0, -- distance at which markers are drawn
    marker = { type = 20, scale = 0.35, r = 245, g = 185, b = 66, a = 190 },
}

---------------------------------------------------------------------------
-- Guards
---------------------------------------------------------------------------
Config.Guards = {
    spawnDistance = 120.0, -- guards spawn when a crew member gets this close
    dropWeapons   = false, -- guards drop their weapon when killed
    headshots     = true,  -- guards can be killed with a single headshot
    -- Suggestions shown in the creator (any valid ped model / weapon can be typed in).
    models = {
        's_m_m_security_01', 's_m_y_blackops_01', 's_m_y_blackops_02', 's_m_m_armoured_01',
        's_m_m_highsec_01', 'g_m_y_lost_01', 'g_m_m_chigoon_01', 'mp_m_securoguard_01',
        's_m_y_swat_01', 'u_m_m_jewelsec_01',
    },
    weapons = {
        'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_MICROSMG', 'WEAPON_SMG',
        'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_NIGHTSTICK',
        'WEAPON_BAT', 'WEAPON_UNARMED',
    },
    -- Behaviours selectable in the creator. The ids are used by client/heist.lua.
    behaviors = {
        { id = 'aggressive', label = '攻撃的 (発見次第追跡)' },
        { id = 'defensive',  label = '防衛的 (持ち場周辺で応戦)' },
        { id = 'stationary', label = '固定 (その場から動かない)' },
        { id = 'patrol',     label = '巡回 (周辺を歩き回る)' },
    },
}

---------------------------------------------------------------------------
-- Doors (ox_doorlock, optional)
-- In the creator each stage can list doors. They are unlocked when the stage
-- is completed, so heists can take place inside locked MLOs.
---------------------------------------------------------------------------
Config.Doors = {
    enabled      = true,
    lockOnStart  = true, -- lock every door of the heist when the crew arrives
    relockOnEnd  = true, -- lock the doors again when the heist ends
    relockDelay  = 60,   -- seconds after the heist ended before the doors lock again
}

---------------------------------------------------------------------------
-- Guidance (objective card, bubbles, GPS)
---------------------------------------------------------------------------
Config.Guidance = {
    waypoint = true,  -- set the GPS waypoint to the current objective
    route    = false, -- additionally draw a blip route
    blips = {
        start      = { sprite = 486, colour = 46, scale = 0.9 },
        stage      = { sprite = 521, colour = 5,  scale = 0.9 },
        loot       = { sprite = 587, colour = 2,  scale = 0.7 },
        finish     = { sprite = 280, colour = 2,  scale = 0.9 }, -- the heist NPC you return to
    },
}

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
Config.Notify = {
    system   = 'hud',  -- 'hud' = Heist HUD bubbles (bottom-right) | 'ox' = ox_lib notifications
    duration = 6000,
    sound    = true,
}

---------------------------------------------------------------------------
-- Security (server-side validation)
---------------------------------------------------------------------------
Config.Security = {
    interactDistance = 6.0, -- max distance (server-side) between a player and the point they interact with
    minStageSeconds  = 1.5, -- a minigame finished faster than this is rejected
    lockTimeout      = 180, -- seconds before an abandoned stage / loot attempt is released
    rateLimitMs      = 250, -- minimum delay between two identical requests of one player
}

---------------------------------------------------------------------------
-- Limits enforced when a heist is saved
---------------------------------------------------------------------------
Config.Limits = {
    stages       = 12,
    stageDoors   = 8,
    guards       = 40,
    loots        = 30,
    rewards      = 25,
    npcs         = 20,
    rewardAmount = 1000000,
    xp           = 1000000,
    cooldown     = 43200, -- minutes
}

---------------------------------------------------------------------------
-- Minigames
-- Each entry: label + desc (shown in the creator), group (tab in the picker),
-- optional resource (must be started) and run(difficulty), executed on the
-- client. run must return true on success. difficulty is 'easy' | 'medium' | 'hard'.
---------------------------------------------------------------------------
Config.MinigameDifficulties = {
    { id = 'easy',   label = '簡単' },
    { id = 'medium', label = '普通' },
    { id = 'hard',   label = '難しい' },
}

-- Tabs of the minigame picker. A tab whose resource is not running is greyed out.
Config.MinigameGroups = {
    { id = 'basic',        label = '標準' },
    { id = 'psui',         label = 'ps-ui',           resource = 'ps-ui' },
    { id = 'aw_reaction',  label = 'Awoken 反応',     resource = 'awoken_minigames' },
    { id = 'aw_memory',    label = 'Awoken 記憶',     resource = 'awoken_minigames' },
    { id = 'aw_logic',     label = 'Awoken パズル',   resource = 'awoken_minigames' },
    { id = 'aw_input',     label = 'Awoken 入力',     resource = 'awoken_minigames' },
    { id = 'aw_precision', label = 'Awoken 精密操作', resource = 'awoken_minigames' },
    { id = 'aw_dexterity', label = 'Awoken 器用さ',   resource = 'awoken_minigames' },
    { id = 'aw_arcade',    label = 'Awoken アーケード', resource = 'awoken_minigames' },
}

Config.Minigames = {
    skillcheck = {
        label = 'スキルチェック',
        desc = '回る針をタイミングよく止める (ox_lib)',
        group = 'basic',
        order = 1,
        run = function(difficulty)
            local presets = {
                easy   = { 'easy', 'easy', 'easy' },
                medium = { 'easy', 'medium', 'medium', 'medium' },
                hard   = { 'medium', 'medium', 'hard', 'hard' },
            }
            return lib.skillCheck(presets[difficulty] or presets.medium, { 'w', 'a', 's', 'd' })
        end,
    },
    pattern = {
        label = 'パターン記憶',
        desc = '光ったマスを覚えてクリックする',
        group = 'basic',
        order = 2,
        run = function(difficulty)
            return StartNuiMinigame('pattern', difficulty)
        end,
    },
    sequence = {
        label = '数字順クリック',
        desc = '1 から順番に数字をクリックする',
        group = 'basic',
        order = 3,
        run = function(difficulty)
            return StartNuiMinigame('sequence', difficulty)
        end,
    },
    progress = {
        label = 'ミニゲームなし',
        desc = 'プログレスバーを待つだけ',
        group = 'basic',
        order = 4,
        run = function(difficulty)
            local duration = { easy = 5000, medium = 8000, hard = 12000 }
            return lib.progressCircle({
                duration = duration[difficulty] or duration.medium,
                label = '作業中...',
                position = 'bottom',
                useWhileDead = false,
                canCancel = true,
                disable = { move = true, car = true, combat = true },
            })
        end,
    },
}

---------------------------------------------------------------------------
-- ps-ui (https://github.com/Project-Sloth/ps-ui)
-- args: values passed to the export after the callback, per difficulty.
---------------------------------------------------------------------------
local psui = {
    { id = 'ps_circle', export = 'Circle', label = 'サークル', desc = '回る線が的に重なった瞬間にキーを押す',
        args = { easy = { 2, 20 }, medium = { 3, 15 }, hard = { 5, 10 } } },           -- circles, seconds
    { id = 'ps_thermite', export = 'Thermite', label = 'テルミット (マス記憶)', desc = '光ったマスの位置を覚えてクリックする',
        args = { easy = { 15, 6, 4 }, medium = { 12, 7, 3 }, hard = { 10, 8, 2 } } },  -- seconds, grid, mistakes
    { id = 'ps_maze', export = 'Maze', label = 'ナンバーメイズ', desc = '数字をたどって正しい道順を見つける',
        args = { easy = { 25 }, medium = { 18 }, hard = { 12 } } },                    -- seconds
    { id = 'ps_varhack', export = 'VarHack', label = 'VARハック', desc = 'ブロックの番号を覚えて順番にクリックする',
        args = { easy = { 3, 20 }, medium = { 5, 15 }, hard = { 7, 12 } } },           -- blocks, seconds
    { id = 'ps_scrambler', export = 'Scrambler', label = 'スクランブラー', desc = '記号の組み合わせを覚えて答える',
        args = { easy = { 'numeric', 30, 0 }, medium = { 'alphabet', 25, 0 }, hard = { 'alphanumeric', 20, 1 } } }, -- type, seconds, mirrored
}

for i = 1, #psui do
    local game = psui[i]
    Config.Minigames[game.id] = {
        label = game.label,
        desc = game.desc,
        group = 'psui',
        resource = 'ps-ui',
        run = function(difficulty)
            return RunPsUi(game.export, game.args[difficulty] or game.args.medium)
        end,
    }
end

---------------------------------------------------------------------------
-- Awoken Minigames (awoken_minigames)
-- Every game uses the settings from awoken_minigames/config/games/*.lua.
-- The stage difficulty decides how many times in a row it has to be cleared
-- (Config.Awoken.rounds). Extra options per game and difficulty can be added
-- in Config.Awoken.options, e.g.
--   options = { skillCheck = { hard = { speed = 90, zoneSize = 12 } } }
---------------------------------------------------------------------------
Config.Awoken = {
    rounds  = { easy = 1, medium = 2, hard = 3 },
    options = {},
    -- Ask awoken_minigames on the SERVER whether the player really won before a
    -- stage counts as completed. Turn off if stages are wrongly rejected.
    serverVerify = true,
}

-- { game key in awoken_minigames, name shown in the creator, short explanation }
local awoken = {
    aw_reaction = {
        { 'skillCheck',    'タイミングバー',       '動くマーカーをゾーンの中で止める' },
        { 'circleClick',   'サークルタイミング',   '回る針が的に重なった瞬間にキーを押す' },
        { 'holdZone',      '長押しリリース',       'キーを長押しして、帯の中で離す' },
        { 'aimTest',       'ターゲット射撃',       '現れる的をすばやくクリックする' },
        { 'balance',       'バランス',             'Q / E で針を中央に保ち続ける' },
        { 'rhythm',        'リズムゲーム',         '落ちてくるノーツに合わせてキーを押す' },
        { 'firewallPulse', 'ファイアウォール突破', '安全ゾーンに入った瞬間に押す' },
        { 'safeCrack',     '金庫ダイヤル',         'ダイヤルを回して暗証番号を探す' },
        { 'lockpick',      'ピッキング',           'リングを回して位置を揃える' },
        { 'osu',           'ビートクリック',       'リズムに合わせて円をクリックする' },
        { 'slider',        'スライダー',           '流れてくる中から正しいものを止める' },
    },
    aw_memory = {
        { 'simonSays',        '光る順番',     '光ったマスの順番を覚えて繰り返す' },
        { 'memory',           'マス記憶',     '光ったマスの配置を覚えて再現する' },
        { 'memoryColors',     '色の記憶',     '色の数を覚えて答える' },
        { 'verbalMemory',     '単語の記憶',   '前に見た単語かどうかを答える' },
        { 'numberedSequence', '番号記憶',     '番号の位置を覚えて順番にクリックする' },
        { 'varHack',          'VARハック',    '動くブロックの番号を覚えて順番にクリックする' },
        { 'pairs',            '神経衰弱',     '同じ絵柄のペアをすべて揃える' },
        { 'recall',           '道順の記憶',   '示された道順を覚えてなぞる' },
        { 'observe',          '観察テスト',   '場面を観察して質問に答える' },
        { 'tally',            '色カウント',   '色付きのマスの数を数える' },
        { 'chromaLock',       'カラーロック', '記憶を頼りに同じ色を作る' },
        { 'pitchLock',        '音合わせ',     '耳で聞いて音の高さを合わせる' },
    },
    aw_logic = {
        { 'hexBreach',    'コード行列ハック',   '行列から正しい順番にコードを選ぶ' },
        { 'codeCrack',    '暗証コード推理',     'ヒントをもとに隠されたコードを当てる' },
        { 'fingerprint',  '指紋照合',           '指紋のパーツを回して揃える' },
        { 'wires',        '配線つなぎ',         '同じ端子どうしを線でつなぐ' },
        { 'splice',       '配線カット',         '故障している箇所だけを切る' },
        { 'pipePressure', '配管パズル',         'パイプを回して水路をつなぐ' },
        { 'current',      '電流バランス',       '負荷が均等になるよう調整する' },
        { 'dataStream',   'データ傍受と解読',   'パケットを捕まえて暗号を解く' },
        { 'symbolSearch', '記号探し',           '指定された記号の並びを探す' },
        { 'lightsOut',    'ライツアウト',       'すべてのマスを点灯させる' },
        { 'untangle',     '線ほどき',           '線が交差しないように点を動かす' },
        { 'arrowMaze',    '見えない迷路',       '見えない道を矢印キーで進む' },
        { 'minefield',    'マインスイーパー',   '地雷を避けてマスを開ける' },
        { 'jigsaw',       'ジグソーパズル',     'タイルを入れ替えて絵を完成させる' },
        { 'towerOfHanoi', 'ハノイの塔',         '円盤を1枚ずつ動かして移し替える' },
        { 'mathRush',     '数の大小くらべ',     'どちらが大きいかをすばやく答える' },
        { 'twenty48',     '2048',               '数字を合体させて目標の数を作る' },
        { 'collapse',     'ブロック消し',       '盤面のブロックをすべて消す' },
        { 'wordCrack',    '英単語当て',         '隠された英単語を推理する (英語)' },
    },
    aw_input = {
        { 'keymash',          '連打',         'キーを連打してゲージをためる' },
        { 'keys',             'タイピング',   '表示された文字をそのまま入力する' },
        { 'numberUp',         '数字順クリック', '数字を小さい順にクリックする' },
        { 'backdoorSequence', 'コマンド入力', '表示された順番どおりにキーを押す' },
    },
    aw_precision = {
        { 'track',     'ターゲット追尾', 'カーソルを動く的に合わせ続ける' },
        { 'trace',     '線なぞり',       '線からはみ出さないようになぞる' },
        { 'cut',       'カッティング',   'ガイドに沿って刃を動かす' },
        { 'calibrate', 'ダイヤル調整',   'それぞれのダイヤルを最適な位置に合わせる' },
        { 'waveform',  '波形合わせ',     '波形を目標と同じ形に合わせる' },
        { 'thread',    'すき間くぐり',   '動くすき間をぶつからずに通り抜ける' },
        { 'reach',     '道さがし',       '通り抜けられる道を見つける' },
    },
    aw_dexterity = {
        { 'shake',    'マウスシェイク', 'マウスを振ってゲージを満たす' },
        { 'cascade',  '落下タイピング', '落ちてくる文字を入力する' },
        { 'fishing',  'フィッシング',   'カーソルを魚に合わせ続ける' },
        { 'cooldown', '冷却作業',       '熱くなったマスをなぞって冷やす' },
    },
    aw_arcade = {
        { 'snake',      'スネーク',       'ぶつからずにヘビを伸ばす' },
        { 'flappy',     'フラッピー',     'すき間を飛び抜ける' },
        { 'stack',      'タワー積み',     'タイミングよく落として積み上げる' },
        { 'pong',       'ポン',           'AI より先に目標点を取る' },
        { 'invaders',   'インベーダー',   '敵をすべて撃ち落とす' },
        { 'crossy',     '道路横断',       '車を避けて上まで渡りきる' },
        { 'ascent',     'ジャンプ登り',   '足場を跳ねて頂上を目指す' },
        { 'slipstream', '車線変更',       '車線を切り替えて車を避ける' },
        { 'stickIt',    'ピン刺し',       '回る的に、他のピンに当てずに刺す' },
        { 'breakout',   'ブロック崩し',   'ボールを打ち返して壁を壊す' },
        { 'matchIt',    '面合わせ',       '正しい面をタイルに向ける' },
    },
}

for group, games in pairs(awoken) do
    for i = 1, #games do
        local key, label, desc = games[i][1], games[i][2], games[i][3]
        Config.Minigames[('aw_%s'):format(key)] = {
            label = label,
            desc = desc,
            group = group,
            order = i,
            resource = 'awoken_minigames',
            awoken = key,
            run = function(difficulty)
                return RunAwoken(key, difficulty, label, desc)
            end,
        }
    end
end

-- Your own minigame: one entry is enough.
-- Config.Minigames.my_hack = {
--     label = 'マイハック', desc = '説明', group = 'basic', resource = 'my_hack',
--     run = function(difficulty) return exports['my_hack']:Start() end,
-- }

-- Settings of the built-in Heist HUD minigames.
Config.NuiMinigames = {
    pattern = {
        easy   = { grid = 4, cells = 4, showMs = 2500, timeMs = 9000 },
        medium = { grid = 5, cells = 6, showMs = 2500, timeMs = 9000 },
        hard   = { grid = 6, cells = 9, showMs = 2200, timeMs = 9000 },
    },
    sequence = {
        easy   = { count = 8,  timeMs = 12000 },
        medium = { count = 12, timeMs = 12000 },
        hard   = { count = 16, timeMs = 12000 },
    },
}
