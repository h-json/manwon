package com.hjson.tenk.domain.challenge.event;

import com.hjson.tenk.domain.challenge.ChallengeResult;

public record ChallengeFinishedEvent(Long challengeId, Long userId, ChallengeResult result) {
}
