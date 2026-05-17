package com.hjson.tenk.security;

public record JwtPrincipal(Long userId) {

    public Long getUserId() {
        return userId;
    }
}
