package com.hjson.tenk.domain.badge;

import com.hjson.tenk.domain.amount.event.AmountRecordedEvent;
import com.hjson.tenk.domain.challenge.event.ChallengeFinishedEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Slf4j
@Component
@RequiredArgsConstructor
public class BadgeEventListener {

    private final BadgeGrantService badgeGrantService;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onAmountRecorded(AmountRecordedEvent event) {
        try {
            badgeGrantService.evaluateForUser(event.userId());
        } catch (Exception e) {
            log.warn("[BadgeEventListener] amount evaluation failed userId={}", event.userId(), e);
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onChallengeFinished(ChallengeFinishedEvent event) {
        try {
            badgeGrantService.grantChallengeSuccess(event.userId(), event.result());
        } catch (Exception e) {
            log.warn("[BadgeEventListener] challenge result handling failed userId={}", event.userId(), e);
        }
    }
}
