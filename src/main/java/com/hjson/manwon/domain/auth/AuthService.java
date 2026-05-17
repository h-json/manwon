package com.hjson.manwon.domain.auth;

import com.hjson.manwon.common.exception.BusinessException;
import com.hjson.manwon.common.exception.ErrorCode;
import com.hjson.manwon.domain.user.AuthProvider;
import com.hjson.manwon.domain.user.User;
import com.hjson.manwon.domain.user.UserRepository;
import com.hjson.manwon.security.JwtTokenProvider;
import com.hjson.manwon.security.KakaoTokenVerifier;
import com.hjson.manwon.security.KakaoTokenVerifier.KakaoUser;
import java.time.LocalDateTime;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AuthService {

    private final UserRepository userRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final KakaoTokenVerifier kakaoTokenVerifier;
    private final JwtTokenProvider jwtTokenProvider;

    @Transactional
    public AuthTokens kakaoLogin(String kakaoAccessToken) {
        KakaoUser kakao = kakaoTokenVerifier.verifyAndFetch(kakaoAccessToken);
        User user = provisionUser(kakao);
        return issueTokens(user);
    }

    @Transactional
    public AuthTokens refresh(String refreshTokenRaw) {
        String hash = jwtTokenProvider.hash(refreshTokenRaw);
        RefreshToken stored = refreshTokenRepository.findByTokenHash(hash)
                .orElseThrow(() -> new BusinessException(ErrorCode.AUTH_REFRESH_TOKEN_INVALID));
        if (!stored.isUsable(LocalDateTime.now())) {
            throw new BusinessException(ErrorCode.AUTH_REFRESH_TOKEN_INVALID);
        }
        User user = stored.getUser();
        if (user.isDeleted()) {
            throw new BusinessException(ErrorCode.USER_ALREADY_WITHDRAWN);
        }
        stored.revoke();
        return issueTokens(user);
    }

    @Transactional
    public void logout(Long userId) {
        refreshTokenRepository.revokeAllByUserId(userId);
    }

    private User provisionUser(KakaoUser kakao) {
        return userRepository
                .findByProviderAndProviderUserId(AuthProvider.KAKAO, kakao.providerUserId())
                .map(existing -> {
                    if (existing.isDeleted()) {
                        throw new BusinessException(ErrorCode.USER_ALREADY_WITHDRAWN);
                    }
                    existing.updateProfile(kakao.email(), kakao.nickname());
                    return existing;
                })
                .orElseGet(() -> userRepository.save(User.create(
                        AuthProvider.KAKAO,
                        kakao.providerUserId(),
                        kakao.email(),
                        kakao.nickname() == null ? "kakao-" + kakao.providerUserId() : kakao.nickname()
                )));
    }

    private AuthTokens issueTokens(User user) {
        String accessToken = jwtTokenProvider.issueAccessToken(user.getId());
        String refreshTokenRaw = jwtTokenProvider.issueRefreshTokenRaw();
        LocalDateTime expiresAt = LocalDateTime.now().plus(jwtTokenProvider.refreshTokenTtl());
        refreshTokenRepository.save(RefreshToken.issue(user, jwtTokenProvider.hash(refreshTokenRaw), expiresAt));
        return new AuthTokens(
                accessToken,
                refreshTokenRaw,
                jwtTokenProvider.accessTokenTtl().toSeconds(),
                user.getId(),
                user.getNickname()
        );
    }
}
