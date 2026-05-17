package com.hjson.tenk.domain.challenge.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import java.time.LocalDateTime;

public record ChallengeCreateRequest(
        @NotNull LocalDateTime startDt,
        @NotNull LocalDateTime endDt,
        @NotNull @Min(1) Integer targetAmount
) {
}
