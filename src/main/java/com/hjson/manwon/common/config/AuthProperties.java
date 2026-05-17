package com.hjson.manwon.common.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "manwon.auth")
public record AuthProperties(Jwt jwt, Kakao kakao) {

    public record Jwt(
            String secret,
            Duration accessTokenTtl,
            Duration refreshTokenTtl,
            String issuer
    ) {}

    public record Kakao(long appId) {}
}
