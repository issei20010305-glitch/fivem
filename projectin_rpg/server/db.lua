--[[ DB初期化・シード ]]
DB = {}

local schema = {
    [[CREATE TABLE IF NOT EXISTS `rpg_characters` (
      `citizenid` VARCHAR(50) NOT NULL, `role` VARCHAR(20) DEFAULT NULL, `role_set_at` INT UNSIGNED DEFAULT NULL,
      `inventory` LONGTEXT DEFAULT NULL, `overflow` LONGTEXT DEFAULT NULL, `stats` LONGTEXT DEFAULT NULL,
      `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`citizenid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `rpg_holdings` (
      `citizenid` VARCHAR(50) NOT NULL, `run_id` VARCHAR(40) NOT NULL, `return_pos` VARCHAR(255) NOT NULL,
      `health` INT NOT NULL DEFAULT 200, `armour` INT NOT NULL DEFAULT 0, `snapshot` LONGTEXT DEFAULT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`citizenid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `rpg_definitions` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `name` VARCHAR(64) NOT NULL, `type` VARCHAR(10) NOT NULL DEFAULT 'dungeon',
      `status` VARCHAR(12) NOT NULL DEFAULT 'draft', `draft_data` LONGTEXT NOT NULL, `published_data` LONGTEXT DEFAULT NULL,
      `version` INT UNSIGNED NOT NULL DEFAULT 0, `has_unpublished` TINYINT(1) NOT NULL DEFAULT 1,
      `created_by` VARCHAR(50) DEFAULT NULL, `updated_by` VARCHAR(50) DEFAULT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `rpg_templates` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `kind` VARCHAR(20) NOT NULL, `name` VARCHAR(64) NOT NULL,
      `data` LONGTEXT NOT NULL, `created_by` VARCHAR(50) DEFAULT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `rpg_events` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `definition_id` INT UNSIGNED NOT NULL, `name` VARCHAR(64) NOT NULL,
      `type` VARCHAR(10) NOT NULL, `location_label` VARCHAR(64) NOT NULL, `announce_at` INT UNSIGNED NOT NULL,
      `start_at` INT UNSIGNED NOT NULL, `end_at` INT UNSIGNED NOT NULL, `status` VARCHAR(12) NOT NULL DEFAULT 'scheduled',
      `reminders_sent` VARCHAR(255) NOT NULL DEFAULT '', `announcement` VARCHAR(255) DEFAULT NULL,
      `created_by` VARCHAR(50) DEFAULT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_status_time` (`status`, `start_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `rpg_claims` (
      `claim_key` VARCHAR(120) NOT NULL, `citizenid` VARCHAR(50) NOT NULL, `items` LONGTEXT DEFAULT NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`claim_key`), KEY `idx_cid` (`citizenid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `rpg_audit_log` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `actor` VARCHAR(64) DEFAULT NULL, `action` VARCHAR(40) NOT NULL,
      `detail` LONGTEXT DEFAULT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `idx_action` (`action`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    [[CREATE TABLE IF NOT EXISTS `rpg_run_history` (
      `run_id` VARCHAR(40) NOT NULL, `definition_id` INT UNSIGNED DEFAULT NULL, `name` VARCHAR(64) DEFAULT NULL,
      `result` VARCHAR(12) NOT NULL, `duration` INT UNSIGNED NOT NULL DEFAULT 0, `players` LONGTEXT DEFAULT NULL,
      `test_mode` TINYINT(1) NOT NULL DEFAULT 0, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`run_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}

DB.Ready = false

function DB.Init()
    for _, q in ipairs(schema) do MySQL.query.await(q) end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM rpg_definitions')
    if (count or 0) == 0 then
        for _, key in ipairs({ 'dungeon', 'raid' }) do
            local clean, err = RPG.Schema.Sanitize(DefaultContent[key])
            if clean then
                local data = json.encode(clean)
                MySQL.insert.await([[INSERT INTO rpg_definitions (name, type, status, draft_data, published_data, version, has_unpublished, created_by)
                    VALUES (?, ?, 'published', ?, ?, 1, 0, 'system')]], { clean.name, clean.type, data, data })
                print(('[projectin_rpg] 初期コンテンツを投入しました: %s'):format(clean.name))
            else
                print(('[projectin_rpg] ^1初期コンテンツの検証に失敗: %s (%s)^0'):format(key, err))
            end
        end
    end

    local tcount = MySQL.scalar.await('SELECT COUNT(*) FROM rpg_templates')
    if (tcount or 0) == 0 then
        for _, t in ipairs(DefaultContent.templates) do
            MySQL.insert.await('INSERT INTO rpg_templates (kind, name, data, created_by) VALUES (?, ?, ?, ?)',
                { t.kind, t.name, json.encode(t.data), 'system' })
        end
    end

    DB.Ready = true
end

function DB.Decode(s, default)
    if type(s) ~= 'string' or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return default
end
