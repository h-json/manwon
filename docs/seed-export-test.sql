-- ============================================================
-- 영상 합본 export 기능 테스트용 시드 데이터
--
-- 무엇:
--   - 확정된(SUCCESS) 7일짜리 챌린지 1개 + 6개의 기록 (지출 3, 무지출 3) + 영상 첨부 3개
--   - 모든 날짜는 오늘 기준 backdated → 챌린지가 즉시 "확정 후" 상태로 export 진입 가능
--   - 영상 파일은 `tenk-backend/uploads/` 에 이미 살아있는 3개 파일을 재사용
--   - 자막 디폴트 다양성을 위해 2개에 memo, 나머지는 폴백
--
-- 어떻게:
--   1. 카카오 로그인 1회 (가장 최근 KAKAO user 가 시드 대상)
--   2. 리포 루트에서: mysql -u tenk -p tenk < docs/seed-export-test.sql
--   3. Flutter 앱 → 챌린지 목록 → 새 챌린지(7일 backdated) 진입 → "영상 만들기" 카드 탭
--
-- 클린업:
--   - 통합 테스트 (./gradlew test) 가 user/challenge/amount/media_file/challenge_badge 를 모두 DELETE 한다.
--     테스트 한 번 돌리고 카카오 재로그인 + 이 시드 재실행이 깔끔한 리셋.
--   - 또는 수동: DELETE FROM challenge WHERE result = 'SUCCESS' AND start_date < CURDATE();
--     (※ media_file 과 amount 가 FK CASCADE 아님 — 아래에 cleanup helper 주석 참고)
-- ============================================================

USE `tenk`;

-- 가장 최근에 가입한 카카오 사용자 (dev 환경엔 보통 1명)
SET @uid := (
    SELECT user_id FROM `user`
    WHERE provider = 'KAKAO' AND is_deleted = 0
    ORDER BY created_dt DESC LIMIT 1
);

-- 안전장치: 사용자가 없으면 친화적으로 멈춤 (NULL @uid 로 INSERT 하면 FK 위반 나서 메시지가 불친절)
-- MariaDB 에는 SIGNAL/ASSERT 가 있지만 스크립트가 가벼우니 그냥 SELECT 로 안내.
SELECT IF(@uid IS NULL,
    '⚠️  KAKAO 사용자가 없어요. Flutter 앱으로 카카오 로그인 1회 먼저.',
    CONCAT('✅ 시드 대상 user_id = ', @uid)
) AS seed_status;

-- 챌린지: today-6 ~ today-1 (6일), 목표 10,000원, 확정 = SUCCESS
INSERT INTO `challenge` (user_id, start_date, end_date, target_amount, result, created_dt, updated_dt)
SELECT @uid, CURDATE() - INTERVAL 6 DAY, CURDATE() - INTERVAL 1 DAY, 10000, 'SUCCESS', NOW(), NOW()
WHERE @uid IS NOT NULL;
SET @cid := LAST_INSERT_ID();

-- ============================================================
-- 기록 6개 (시간순)
--
-- Day 1 (today-6): 지출 2,000  카페·아메리카노   memo: "출근길 마지막 카페인" → 영상 1
-- Day 2 (today-5): 무지출                                                  → 텍스트 카드 (영상 없음)
-- Day 3 (today-4): 지출 3,000  식비·김밥 한 줄                              → 영상 2
-- Day 4 (today-3): 무지출      memo: "도시락 챙겼다"                        → 텍스트 카드
-- Day 5 (today-2): 지출 1,500  교통·버스                                    → 영상 3
-- Day 6 (today-1): 무지출                                                  → 텍스트 카드
--
-- 총 지출 6,500 / 목표 10,000 → 잔액 3,500 → SUCCESS
-- ============================================================

-- Day 1: 지출 + 영상 1
INSERT INTO `amount` (challenge_id, category, content, amount, is_no_spend, memo, spent_dt)
VALUES (@cid, '카페', '아메리카노', 2000, 0, '출근길 마지막 카페인',
        DATE_SUB(CURDATE(), INTERVAL 6 DAY) + INTERVAL 9 HOUR + INTERVAL 30 MINUTE);
SET @a1 := LAST_INSERT_ID();
INSERT INTO `media_file` (amount_id, file_path, original_name)
VALUES (@a1, 'amounts/7/2026/05/19/11a93d1f-3be7-4117-af4e-657923356ecd.mp4', 'clip1.mp4');

-- Day 2: 무지출 (영상 없음)
INSERT INTO `amount` (challenge_id, category, content, amount, is_no_spend, memo, spent_dt)
VALUES (@cid, NULL, NULL, 0, 1, NULL,
        DATE_SUB(CURDATE(), INTERVAL 5 DAY) + INTERVAL 22 HOUR);

-- Day 3: 지출 + 영상 2
INSERT INTO `amount` (challenge_id, category, content, amount, is_no_spend, memo, spent_dt)
VALUES (@cid, '식비', '김밥 한 줄', 3000, 0, NULL,
        DATE_SUB(CURDATE(), INTERVAL 4 DAY) + INTERVAL 12 HOUR + INTERVAL 15 MINUTE);
SET @a3 := LAST_INSERT_ID();
INSERT INTO `media_file` (amount_id, file_path, original_name)
VALUES (@a3, 'amounts/7/2026/05/19/2540ebf3-ac25-4949-9700-e9bdf9790321.mp4', 'clip2.mp4');

-- Day 4: 무지출 + memo
INSERT INTO `amount` (challenge_id, category, content, amount, is_no_spend, memo, spent_dt)
VALUES (@cid, NULL, NULL, 0, 1, '도시락 챙겼다',
        DATE_SUB(CURDATE(), INTERVAL 3 DAY) + INTERVAL 21 HOUR);

-- Day 5: 지출 + 영상 3
INSERT INTO `amount` (challenge_id, category, content, amount, is_no_spend, memo, spent_dt)
VALUES (@cid, '교통', '버스', 1500, 0, NULL,
        DATE_SUB(CURDATE(), INTERVAL 2 DAY) + INTERVAL 18 HOUR + INTERVAL 40 MINUTE);
SET @a5 := LAST_INSERT_ID();
INSERT INTO `media_file` (amount_id, file_path, original_name)
VALUES (@a5, 'amounts/8/2026/05/19/f77eb277-98ee-475b-9ebd-9075a80408f1.mp4', 'clip3.mp4');

-- Day 6: 무지출
INSERT INTO `amount` (challenge_id, category, content, amount, is_no_spend, memo, spent_dt)
VALUES (@cid, NULL, NULL, 0, 1, NULL,
        DATE_SUB(CURDATE(), INTERVAL 1 DAY) + INTERVAL 23 HOUR);

-- ============================================================
-- 배지: CHALLENGE_SUCCESS 1개 + NO_SPEND 3 (무지출 3일 누적)
-- 단순 시각 완성도용. 실제 운영에선 BadgeGrantService 가 발급.
-- ============================================================

SET @badge_success := (SELECT badge_id FROM `badge` WHERE type = 'CHALLENGE_SUCCESS' AND condition_value = 1);
SET @badge_no_spend_3 := (SELECT badge_id FROM `badge` WHERE type = 'NO_SPEND' AND condition_value = 3);

INSERT INTO `challenge_badge` (challenge_id, badge_id, created_dt)
SELECT @cid, @badge_success, NOW() WHERE @badge_success IS NOT NULL;

INSERT INTO `challenge_badge` (challenge_id, badge_id, created_dt)
SELECT @cid, @badge_no_spend_3, NOW() WHERE @badge_no_spend_3 IS NOT NULL;

-- ============================================================
-- 최종 확인
-- ============================================================
SELECT
    @cid AS challenge_id,
    (SELECT COUNT(*) FROM amount WHERE challenge_id = @cid) AS amount_count,
    (SELECT COUNT(*) FROM amount WHERE challenge_id = @cid AND is_no_spend = 0) AS spend_count,
    (SELECT COUNT(*) FROM amount WHERE challenge_id = @cid AND is_no_spend = 1) AS no_spend_count,
    (SELECT COUNT(*) FROM media_file mf JOIN amount a ON mf.amount_id = a.amount_id WHERE a.challenge_id = @cid) AS video_count,
    (SELECT COUNT(*) FROM challenge_badge WHERE challenge_id = @cid) AS badge_count,
    (SELECT SUM(amount) FROM amount WHERE challenge_id = @cid) AS total_spent;

-- ============================================================
-- 수동 cleanup (필요 시)
-- ============================================================
-- DELETE mf FROM media_file mf JOIN amount a ON mf.amount_id = a.amount_id WHERE a.challenge_id = @cid;
-- DELETE FROM amount           WHERE challenge_id = @cid;
-- DELETE FROM challenge_badge  WHERE challenge_id = @cid;
-- DELETE FROM challenge        WHERE challenge_id = @cid;
