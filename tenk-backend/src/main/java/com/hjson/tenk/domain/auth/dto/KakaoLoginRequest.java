package com.hjson.tenk.domain.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record KakaoLoginRequest(
        @NotBlank(message = "카카오 액세스 토큰이 필요합니다.")
        String accessToken
) {}
