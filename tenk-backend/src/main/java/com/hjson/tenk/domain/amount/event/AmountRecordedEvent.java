package com.hjson.tenk.domain.amount.event;

public record AmountRecordedEvent(Long amountId, Long userId, Long challengeId) {
}
