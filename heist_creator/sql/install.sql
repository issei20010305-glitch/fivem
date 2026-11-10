-- Heist Creator - database installation
-- Run this file once against your server database.
-- (With Config.Database.autoInstall = true the resource also creates these tables on start.)

CREATE TABLE IF NOT EXISTS `heist_creator_heists` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name`       VARCHAR(64)  NOT NULL,
    `data`       LONGTEXT     NOT NULL,
    `enabled`    TINYINT(1)   NOT NULL DEFAULT 1,
    `created_by` VARCHAR(64)  DEFAULT NULL,
    `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `heist_creator_players` (
    `citizenid` VARCHAR(64) NOT NULL,
    `xp`        INT         NOT NULL DEFAULT 0,
    `completed` INT         NOT NULL DEFAULT 0,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `heist_creator_cooldowns` (
    `heist_id`   INT UNSIGNED NOT NULL,
    `owner`      VARCHAR(64)  NOT NULL,          -- citizenid, or '__global' for the server-wide cooldown
    `expires_at` INT UNSIGNED NOT NULL,          -- unix timestamp
    PRIMARY KEY (`heist_id`, `owner`),
    KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `heist_creator_settings` (
    `name`  VARCHAR(64) NOT NULL,
    `value` LONGTEXT    NOT NULL,
    PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
