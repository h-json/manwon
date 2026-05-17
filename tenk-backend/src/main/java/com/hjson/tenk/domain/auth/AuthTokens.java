package com.hjson.tenk.domain.auth;

public record AuthTokens(
        String accessToken,
        String refreshToken,
        long accessTokenExpiresIn,
        Long userId,
        String nickname
) {}
