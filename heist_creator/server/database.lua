-- All SQL used by the resource.
DB = {}

local GLOBAL_OWNER = '__global'
DB.GLOBAL_OWNER = GLOBAL_OWNER

local schema = {
    [[CREATE TABLE IF NOT EXISTS `heist_creator_heists` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `name` VARCHAR(64) NOT NULL,
        `data` LONGTEXT NOT NULL,
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        `created_by` VARCHAR(64) DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `heist_creator_players` (
        `citizenid` VARCHAR(64) NOT NULL,
        `xp` INT NOT NULL DEFAULT 0,
        `completed` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `heist_creator_cooldowns` (
        `heist_id` INT UNSIGNED NOT NULL,
        `owner` VARCHAR(64) NOT NULL,
        `expires_at` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`heist_id`, `owner`),
        KEY `idx_expires` (`expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `heist_creator_settings` (
        `name` VARCHAR(64) NOT NULL,
        `value` LONGTEXT NOT NULL,
        PRIMARY KEY (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}

function DB.Install()
    for i = 1, #schema do
        MySQL.query.await(schema[i])
    end
end

---------------------------------------------------------------------------
-- Heists
---------------------------------------------------------------------------
function DB.LoadHeists()
    return MySQL.query.await('SELECT `id`, `name`, `data`, `enabled` FROM `heist_creator_heists`') or {}
end

---@return number? insertId
function DB.InsertHeist(name, data, enabled, createdBy)
    return MySQL.insert.await(
        'INSERT INTO `heist_creator_heists` (`name`, `data`, `enabled`, `created_by`) VALUES (?, ?, ?, ?)',
        { name, json.encode(data), enabled and 1 or 0, createdBy })
end

function DB.UpdateHeist(id, name, data, enabled)
    return MySQL.update.await(
        'UPDATE `heist_creator_heists` SET `name` = ?, `data` = ?, `enabled` = ? WHERE `id` = ?',
        { name, json.encode(data), enabled and 1 or 0, id })
end

function DB.SetHeistEnabled(id, enabled)
    return MySQL.update.await('UPDATE `heist_creator_heists` SET `enabled` = ? WHERE `id` = ?',
        { enabled and 1 or 0, id })
end

function DB.DeleteHeist(id)
    MySQL.update.await('DELETE FROM `heist_creator_cooldowns` WHERE `heist_id` = ?', { id })
    return MySQL.update.await('DELETE FROM `heist_creator_heists` WHERE `id` = ?', { id })
end

---------------------------------------------------------------------------
-- Heist XP
---------------------------------------------------------------------------
---@return number
function DB.GetXP(citizenid)
    return MySQL.scalar.await('SELECT `xp` FROM `heist_creator_players` WHERE `citizenid` = ?', { citizenid }) or 0
end

function DB.AddXP(citizenid, amount, completed)
    MySQL.update(
        [[INSERT INTO `heist_creator_players` (`citizenid`, `xp`, `completed`) VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE `xp` = GREATEST(0, `xp` + ?), `completed` = `completed` + ?]],
        { citizenid, math.max(0, amount), completed, amount, completed })
end

function DB.SetXP(citizenid, amount)
    MySQL.update(
        [[INSERT INTO `heist_creator_players` (`citizenid`, `xp`) VALUES (?, ?)
          ON DUPLICATE KEY UPDATE `xp` = ?]],
        { citizenid, amount, amount })
end

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
function DB.LoadCooldowns()
    MySQL.update.await('DELETE FROM `heist_creator_cooldowns` WHERE `expires_at` <= ?', { os.time() })
    return MySQL.query.await('SELECT `heist_id`, `owner`, `expires_at` FROM `heist_creator_cooldowns`') or {}
end

function DB.SetCooldown(heistId, owner, expiresAt)
    MySQL.update(
        [[INSERT INTO `heist_creator_cooldowns` (`heist_id`, `owner`, `expires_at`) VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE `expires_at` = ?]],
        { heistId, owner, expiresAt, expiresAt })
end

function DB.ClearCooldowns(heistId)
    MySQL.update('DELETE FROM `heist_creator_cooldowns` WHERE `heist_id` = ?', { heistId })
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function DB.GetSetting(name)
    local value = MySQL.scalar.await('SELECT `value` FROM `heist_creator_settings` WHERE `name` = ?', { name })
    return value and json.decode(value) or nil
end

function DB.SetSetting(name, value)
    local encoded = json.encode(value)
    MySQL.update.await(
        [[INSERT INTO `heist_creator_settings` (`name`, `value`) VALUES (?, ?)
          ON DUPLICATE KEY UPDATE `value` = ?]],
        { name, encoded, encoded })
end
