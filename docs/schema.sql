-- ============================================================
-- Manwon 백엔드 DDL
-- ddl-auto=validate 이므로 운영 전 이 스크립트를 수동 적용해야 함.
-- ERD 대비 변경 사항:
--   user          : password 제거, provider/provider_user_id/email 추가
--   amount        : created_dt 추가, is_no_spend 추가, category/content NULL 허용
--   challenge     : result 컬럼 추가 (NULL=진행중 / SUCCESS / FAIL)
--   refresh_token : 신설 — JWT 모바일 인증의 RT 보관소
-- ============================================================

-- 외래키 순서를 고려한 드롭
DROP TABLE IF EXISTS `refresh_token`;
DROP TABLE IF EXISTS `user_badge`;
DROP TABLE IF EXISTS `badge`;
DROP TABLE IF EXISTS `media_file`;
DROP TABLE IF EXISTS `amount`;
DROP TABLE IF EXISTS `challenge`;
DROP TABLE IF EXISTS `user`;

CREATE TABLE `user` (
    `user_id`           BIGINT AUTO_INCREMENT                            NOT NULL,
    `provider`          ENUM('GOOGLE', 'KAKAO', 'NAVER')                 NOT NULL,
    `provider_user_id`  VARCHAR(255)                                     NOT NULL,
    `email`             VARCHAR(255)                                     NULL,
    `nickname`          VARCHAR(255)                                     NOT NULL,
    `created_dt`        DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    `updated_dt`        DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    `is_deleted`        TINYINT(1)    DEFAULT 0                          NOT NULL,
    `deleted_dt`        DATETIME                                         NULL,
    PRIMARY KEY (`user_id`),
    UNIQUE KEY `uk_user_provider` (`provider`, `provider_user_id`)
);

CREATE TABLE `challenge` (
    `challenge_id`      BIGINT AUTO_INCREMENT                            NOT NULL,
    `user_id`           BIGINT                                           NOT NULL,
    `start_dt`          DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    `end_dt`            DATETIME                                         NOT NULL,
    `target_amount`     INT           DEFAULT 10000                      NOT NULL,
    `result`            ENUM('SUCCESS', 'FAIL')                          NULL,
    `created_dt`        DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    `updated_dt`        DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    `is_deleted`        TINYINT(1)    DEFAULT 0                          NOT NULL,
    `deleted_dt`        DATETIME                                         NULL,
    PRIMARY KEY (`challenge_id`),
    KEY `idx_challenge_user` (`user_id`),
    CONSTRAINT `fk_challenge_user`
        FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`)
);

CREATE TABLE `amount` (
    `amount_id`         BIGINT AUTO_INCREMENT                            NOT NULL,
    `challenge_id`      BIGINT                                           NOT NULL,
    `category`          VARCHAR(255)                                     NULL,
    `content`           VARCHAR(255)                                     NULL,
    `amount`            INT                                              NOT NULL,
    `is_no_spend`       TINYINT(1)    DEFAULT 0                          NOT NULL,
    `created_dt`        DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    PRIMARY KEY (`amount_id`),
    KEY `idx_amount_challenge` (`challenge_id`),
    KEY `idx_amount_challenge_created` (`challenge_id`, `created_dt`),
    CONSTRAINT `fk_amount_challenge`
        FOREIGN KEY (`challenge_id`) REFERENCES `challenge` (`challenge_id`)
);

CREATE TABLE `media_file` (
    `file_id`           BIGINT AUTO_INCREMENT                            NOT NULL,
    `amount_id`         BIGINT                                           NOT NULL,
    `file_path`         VARCHAR(255)                                     NOT NULL,
    `original_name`     VARCHAR(255)                                     NOT NULL,
    PRIMARY KEY (`file_id`),
    KEY `idx_media_file_amount` (`amount_id`),
    CONSTRAINT `fk_media_file_amount`
        FOREIGN KEY (`amount_id`) REFERENCES `amount` (`amount_id`)
);

CREATE TABLE `badge` (
    `badge_id`          BIGINT AUTO_INCREMENT                            NOT NULL,
    `type`              ENUM('STREAK', 'NO_SPEND', 'CHALLENGE_SUCCESS')  NOT NULL,
    `condition_value`   INT                                              NOT NULL,
    `icon_path`         VARCHAR(255)                                     NOT NULL,
    PRIMARY KEY (`badge_id`),
    UNIQUE KEY `uk_badge_type_value` (`type`, `condition_value`)
);

CREATE TABLE `user_badge` (
    `user_badge_id`     BIGINT AUTO_INCREMENT                            NOT NULL,
    `user_id`           BIGINT                                           NOT NULL,
    `badge_id`          BIGINT                                           NOT NULL,
    `created_dt`        DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    PRIMARY KEY (`user_badge_id`),
    UNIQUE KEY `uk_user_badge` (`user_id`, `badge_id`),
    KEY `idx_user_badge_user` (`user_id`),
    CONSTRAINT `fk_user_badge_user`
        FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`),
    CONSTRAINT `fk_user_badge_badge`
        FOREIGN KEY (`badge_id`) REFERENCES `badge` (`badge_id`)
);

CREATE TABLE `refresh_token` (
    `refresh_token_id`  BIGINT AUTO_INCREMENT                            NOT NULL,
    `user_id`           BIGINT                                           NOT NULL,
    `token_hash`        VARCHAR(255)                                     NOT NULL,
    `expires_at`        DATETIME                                         NOT NULL,
    `revoked`           TINYINT(1)    DEFAULT 0                          NOT NULL,
    `created_dt`        DATETIME      DEFAULT CURRENT_TIMESTAMP          NOT NULL,
    PRIMARY KEY (`refresh_token_id`),
    UNIQUE KEY `uk_refresh_token_hash` (`token_hash`),
    KEY `idx_refresh_token_user` (`user_id`),
    CONSTRAINT `fk_refresh_token_user`
        FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`)
);

-- ============================================================
-- 배지 마스터 데이터 (3 / 7 / 14 / 30 단계)
-- icon_path 는 추후 실제 리소스에 맞춰 갱신
-- ============================================================
INSERT INTO `badge` (`type`, `condition_value`, `icon_path`) VALUES
    ('STREAK',            3,  '/badges/streak_3.png'),
    ('STREAK',            7,  '/badges/streak_7.png'),
    ('STREAK',            14, '/badges/streak_14.png'),
    ('STREAK',            30, '/badges/streak_30.png'),
    ('NO_SPEND',          3,  '/badges/no_spend_3.png'),
    ('NO_SPEND',          7,  '/badges/no_spend_7.png'),
    ('NO_SPEND',          14, '/badges/no_spend_14.png'),
    ('NO_SPEND',          30, '/badges/no_spend_30.png'),
    ('CHALLENGE_SUCCESS', 1,  '/badges/challenge_success.png');
