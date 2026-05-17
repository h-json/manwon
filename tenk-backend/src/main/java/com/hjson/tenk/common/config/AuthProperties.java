package com.hjson.tenk.common.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "tenk.auth")
public record AuthProperties(Jwt jwt, Kakao kakao) {

    public record Jwt(
            String secret,
            Duration accessTokenTtl,
            Duration refreshTokenTtl,
            String issuer
    ) {}

    public record Kakao(long appId) {}
}
