package com.hjson.tenk.domain.challenge.dto;

import com.hjson.tenk.domain.challenge.Challenge;
import com.hjson.tenk.domain.challenge.ChallengeResult;
import java.time.LocalDateTime;

public record ChallengeResponse(
        Long challengeId,
        LocalDateTime startDt,
        LocalDateTime endDt,
        int targetAmount,
        long totalSpent,
        long balance,
        ChallengeResult result,
        boolean finished
) {
    public static ChallengeResponse of(Challenge challenge, long totalSpent, LocalDateTime now) {
        return new ChallengeResponse(
                challenge.getId(),
                challenge.getStartDt(),
                challenge.getEndDt(),
                challenge.getTargetAmount(),
                totalSpent,
                challenge.getTargetAmount() - totalSpent,
                challenge.getResult(),
                challenge.isFinished(now)
        );
    }
}
