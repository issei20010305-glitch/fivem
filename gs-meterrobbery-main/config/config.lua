-- EC Parking Meter Robbery - Config
-- This version adds explanatory comments to every section/option.

Config = {}

-- Framework Configuration
-- 'qb'   -> Force QBCore
-- 'esx'  -> Force ESX
-- 'auto' -> Try to detect automatically
Config.Framework = 'auto'

-- Target System Configuration
-- 'ox'   -> ox_target
-- 'qb'   -> qb-target
-- 'auto' -> Try to detect automatically
Config.Target = 'auto'

-- Cooldown Configuration
-- Controls how often players can rob meters
Config.Cooldown = {
    enabled = true,         -- Enable/disable cooldown system
    global = 60,            -- Global cooldown in seconds (all players, all meters)
    player = 300,           -- Per-player cooldown in seconds (specific player, all meters)
    meter = 1800,           -- Per-meter cooldown in seconds (all players, specific meter)
    notify = true           -- Show notification when player tries during cooldown
}

-- Dispatch System Configuration
Config.Dispatch = {
    enabled = true,         -- Enable/disable dispatch alerts entirely
    system = 'ps',          -- 'ps' (ps-dispatch), 'cd' (cd_dispatch), or 'custom' (your own integration)
    cooldown = 60000,       -- Minimum time (in ms) between dispatch calls for this script (e.g., 60000 = 1 minute)
}

-- Item Requirements (what players must have to attempt a robbery)
Config.RequiredItems = {
    enabled = true,         -- If false, no items are required
    items = {
        -- name:   item name in your inventory system
        -- label:  display label used by notifications/feedback
        -- amount: how many of this item are required to start
        -- remove: whether to remove the item on use
        -- chance: % chance to remove the item when used (0–100)
        { name = 'lockpick', label = 'Lockpick', amount = 1, remove = true, chance = 65 }
    }
}

-- Reward Configuration (what players can receive on success)
Config.Rewards = {
    money = {
        enabled = true,     -- Toggle money rewards
        type = 'cash',      -- 'cash', 'bank', 'black_money', 'crypto' (uses your framework/wallet integrations)
        minAmount = 50,     -- Minimum payout
        maxAmount = 200,    -- Maximum payout
    },
    items = {
        enabled = true,     -- Toggle item rewards
        possible = {
            -- Each entry has:
            -- name: item name
            -- label: display label
            -- min/max: quantity range
            -- chance: % chance this item will be awarded (rolls independently)
            { name = 'metalscrap',   label = 'Metal Scrap',    min = 1, max = 3, chance = 70 },
            { name = 'copper',       label = 'Copper',         min = 1, max = 2, chance = 50 },
            { name = 'aluminum',     label = 'Aluminum',       min = 1, max = 2, chance = 40 },
            { name = 'iron',         label = 'Iron',           min = 1, max = 2, chance = 30 },
            { name = 'steel',        label = 'Steel',          min = 1, max = 1, chance = 20 },
            { name = 'rubber',       label = 'Rubber',         min = 1, max = 3, chance = 60 },
            { name = 'electronic_kit', label = 'Electronic Kit', min = 1, max = 1, chance = 10 },
        }
    }
}

-- Minigame Configuration
-- 'type' and 'difficulty' define the primary challenge; the nested tables define difficulty presets per game type.
Config.Minigame = {
    type = 'circle',         -- 'circle', 'maze', 'lockpick'
    difficulty = 'medium',   -- 'easy', 'medium', 'hard'

    -- Circle minigame: number of circles per difficulty
    circle = {
        easy   = { circles = 3 },   -- Easier timing windows, fewer circles
        medium = { circles = 4 },
        hard   = { circles = 5 },   -- Harder timing windows, more circles
    },

    -- Maze minigame: maze size per difficulty
    maze = {
        easy   = { size = 'small' },   -- Small grid
        medium = { size = 'medium' },  -- Medium grid
        hard   = { size = 'large' },   -- Large grid
    },

    -- Lockpick minigame: number of pins per difficulty
    lockpick = {
        easy   = { pins = 4 },     -- Fewer pins, easier
        medium = { pins = 5 },
        hard   = { pins = 6 },     -- More pins, harder
    }
}

-- Meter Configuration (targets and interaction behavior)
Config.Meters = {
    -- Default parking meter model (used if a specific model isn't found)
    model = 'prop_parknmeter_01',

    -- All valid parking meter models that can be targeted
    models = {
        'prop_parknmeter_01',
        'prop_parknmeter_02'
    },

    -- Police presence rules
    police = {
        required = false,         -- If true, require a minimum number of police online to allow robberies
        minimum = 2,              -- Minimum police count (used only if required = true)
        jobs = { 'police', 'sheriff' }, -- Job names that count as police (framework-specific)
    },

    -- Base success chance for the robbery (before modifiers)
    successChance = 70,           -- Percentage (0–100)

    -- Interaction distance with the meter
    interactionDistance = 1.5,    -- In meters

    -- Animation played while attempting the robbery
    animation = {
        dict = 'mini@repair',     -- Animation dictionary
        anim = 'fixing_a_ped',    -- Animation name
        flag = 16,                -- Task flag (e.g., loop, upper body only, etc.)
        duration = 10000,         -- Duration in ms (e.g., 10000 = 10 seconds)
    }
}

-- Debug Mode
-- When true, prints extra logs and may show test notifications to help diagnose issues.
Config.Debug = false