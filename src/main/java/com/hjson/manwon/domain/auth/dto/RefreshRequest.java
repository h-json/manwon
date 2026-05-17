package com.hjson.manwon.domain.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record RefreshRequest(
        @NotBlank(message = "리프레시 토큰이 필요합니다.")
        String refreshToken
) {}
