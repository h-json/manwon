package com.hjson.tenk.domain.badge;

import com.hjson.tenk.domain.challenge.ChallengeService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class BadgeScheduler {

    private final BadgeGrantService badgeGrantService;
    private final ChallengeService challengeService;

    /** 매일 새벽 1시: 종료된 챌린지 결과 확정 + 전체 사용자 배지 재평가 */
    @Scheduled(cron = "0 0 1 * * *", zone = "Asia/Seoul")
    public void dailyReconciliation() {
        log.info("[BadgeScheduler] daily reconciliation start");
        int finalized = challengeService.finalizeAllDue();
        log.info("[BadgeScheduler] finalized challenges={}", finalized);
        badgeGrantService.evaluateAllUsers();
        log.info("[BadgeScheduler] daily reconciliation done");
    }
}
