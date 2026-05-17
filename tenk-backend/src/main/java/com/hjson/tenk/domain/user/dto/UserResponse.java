package com.hjson.tenk.domain.user.dto;

import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;

public record UserResponse(
        Long userId,
        AuthProvider provider,
        String email,
        String nickname
) {
    public static UserResponse from(User user) {
        return new UserResponse(user.getId(), user.getProvider(), user.getEmail(), user.getNickname());
    }
}
