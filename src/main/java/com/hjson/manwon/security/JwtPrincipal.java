package com.hjson.manwon.security;

public record JwtPrincipal(Long userId) {

    public Long getUserId() {
        return userId;
    }
}
