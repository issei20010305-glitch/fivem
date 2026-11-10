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

-- Alert sent to police when a crew reaches the starting point.
Config.PoliceAlert = {
    enabled      = true,
    blipSeconds  = 90,
    blipSprite   = 161,
    blipColour   = 1,
    -- Optional server-side hook for a custom dispatch resource.
    -- Return true to skip the built-in alert.
    ---@param coords vector3
    ---@param heistName string
    custom = function(coords, heistName)
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
    -- Members further away than this from the extraction point when the heist is
    -- completed do not count as participants (no XP). 0 = no distance check.
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
Config.Cooldowns = {
    -- Apply cooldowns when a heist fails / is cancelled after the crew reached the starting point.
    applyOnFail = true,
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
        extraction = { sprite = 358, colour = 3,  scale = 0.9 },
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
-- Each entry: label (shown in the creator) + run(difficulty) executed on the
-- client. run must return true on success. difficulty is 'easy' | 'medium' | 'hard'.
-- To add your own minigame simply add an entry that calls its export.
---------------------------------------------------------------------------
Config.MinigameDifficulties = {
    { id = 'easy',   label = '簡単' },
    { id = 'medium', label = '普通' },
    { id = 'hard',   label = '難しい' },
}

Config.Minigames = {
    skillcheck = {
        label = 'スキルチェック (ox_lib)',
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
        label = 'パターン記憶 (Heist HUD)',
        run = function(difficulty)
            return StartNuiMinigame('pattern', difficulty)
        end,
    },
    sequence = {
        label = 'ナンバーシーケンス (Heist HUD)',
        run = function(difficulty)
            return StartNuiMinigame('sequence', difficulty)
        end,
    },
    progress = {
        label = 'なし (プログレスバーのみ)',
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
    -- Example of an external minigame:
    -- howdy_hack = {
    --     label = 'Howdy Hack',
    --     run = function(difficulty)
    --         return exports['howdy-hackminigame']:Begin(3, 5000)
    --     end,
    -- },
}

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
