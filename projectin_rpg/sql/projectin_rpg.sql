-- projectin_rpg 用テーブル (既存のQbox/ox_inventoryテーブルには一切変更を加えません)
-- リソース起動時にも CREATE TABLE IF NOT EXISTS で自動作成されますが、
-- 事前に手動で流し込むことを推奨します。

CREATE TABLE IF NOT EXISTS `rpg_characters` (
  `citizenid`   VARCHAR(50)  NOT NULL,
  `role`        VARCHAR(20)  DEFAULT NULL,
  `role_set_at` INT UNSIGNED DEFAULT NULL,
  `inventory`   LONGTEXT     DEFAULT NULL,  -- RPG専用インベントリ (JSON)
  `overflow`    LONGTEXT     DEFAULT NULL,  -- 容量超過で受け取れなかった報酬 (JSON)
  `stats`       LONGTEXT     DEFAULT NULL,  -- クリア数/討伐数など (JSON)
  `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 入場中に退避した通常インベントリの管理 (実体は ox_inventory のスタッシュ rpghold_<citizenid>)
CREATE TABLE IF NOT EXISTS `rpg_holdings` (
  `citizenid`   VARCHAR(50)  NOT NULL,
  `run_id`      VARCHAR(40)  NOT NULL,
  `return_pos`  VARCHAR(255) NOT NULL,
  `health`      INT          NOT NULL DEFAULT 200,
  `armour`      INT          NOT NULL DEFAULT 0,
  `snapshot`    LONGTEXT     DEFAULT NULL, -- 監査用: 入場時の所持品一覧
  `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ダンジョン/レイド定義 (draft_data = 編集中, published_data = 公開版)
CREATE TABLE IF NOT EXISTS `rpg_definitions` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`           VARCHAR(64)  NOT NULL,
  `type`           VARCHAR(10)  NOT NULL DEFAULT 'dungeon',
  `status`         VARCHAR(12)  NOT NULL DEFAULT 'draft',  -- draft / published / archived
  `draft_data`     LONGTEXT     NOT NULL,
  `published_data` LONGTEXT     DEFAULT NULL,
  `version`        INT UNSIGNED NOT NULL DEFAULT 0,
  `has_unpublished` TINYINT(1)  NOT NULL DEFAULT 1,
  `created_by`     VARCHAR(50)  DEFAULT NULL,
  `updated_by`     VARCHAR(50)  DEFAULT NULL,
  `created_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `rpg_templates` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `kind`       VARCHAR(20)  NOT NULL,  -- definition / enemy
  `name`       VARCHAR(64)  NOT NULL,
  `data`       LONGTEXT     NOT NULL,
  `created_by` VARCHAR(50)  DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 期間限定イベント (時刻はUTCエポック秒で保存、表示は日本時間)
CREATE TABLE IF NOT EXISTS `rpg_events` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `definition_id`  INT UNSIGNED NOT NULL,
  `name`           VARCHAR(64)  NOT NULL,
  `type`           VARCHAR(10)  NOT NULL,
  `location_label` VARCHAR(64)  NOT NULL,
  `announce_at`    INT UNSIGNED NOT NULL,
  `start_at`       INT UNSIGNED NOT NULL,
  `end_at`         INT UNSIGNED NOT NULL,
  `status`         VARCHAR(12)  NOT NULL DEFAULT 'scheduled', -- scheduled / announced / active / ended / cancelled
  `reminders_sent` VARCHAR(255) NOT NULL DEFAULT '',
  `announcement`   VARCHAR(255) DEFAULT NULL,  -- 個別告知文 (空ならテンプレート)
  `created_by`     VARCHAR(50)  DEFAULT NULL,
  `created_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_status_time` (`status`, `start_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 報酬/ドロップの二重付与防止 (UNIQUE制約)
CREATE TABLE IF NOT EXISTS `rpg_claims` (
  `claim_key`  VARCHAR(120) NOT NULL,
  `citizenid`  VARCHAR(50)  NOT NULL,
  `items`      LONGTEXT     DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`claim_key`),
  KEY `idx_cid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `rpg_audit_log` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor`      VARCHAR(64)  DEFAULT NULL,
  `action`     VARCHAR(40)  NOT NULL,
  `detail`     LONGTEXT     DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `rpg_run_history` (
  `run_id`        VARCHAR(40)  NOT NULL,
  `definition_id` INT UNSIGNED DEFAULT NULL,
  `name`          VARCHAR(64)  DEFAULT NULL,
  `result`        VARCHAR(12)  NOT NULL,
  `duration`      INT UNSIGNED NOT NULL DEFAULT 0,
  `players`       LONGTEXT     DEFAULT NULL,
  `test_mode`     TINYINT(1)   NOT NULL DEFAULT 0,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`run_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
