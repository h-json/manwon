package com.hjson.tenk.domain.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;
import com.hjson.tenk.domain.user.UserRepository;
import com.hjson.tenk.security.JwtTokenProvider;
import com.hjson.tenk.security.KakaoTokenVerifier;
import com.hjson.tenk.security.KakaoTokenVerifier.KakaoUser;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class AuthServiceTest {

    @Mock UserRepository userRepository;
    @Mock RefreshTokenRepository refreshTokenRepository;
    @Mock KakaoTokenVerifier kakaoTokenVerifier;
    @Mock JwtTokenProvider jwtTokenProvider;

    @InjectMocks AuthService service;

    @BeforeEach
    void setUp() {
        given(jwtTokenProvider.issueAccessToken(anyLong())).willReturn("AT");
        given(jwtTokenProvider.issueRefreshTokenRaw()).willReturn("RT-raw");
        given(jwtTokenProvider.hash("RT-raw")).willReturn("RT-hash-new");
        given(jwtTokenProvider.accessTokenTtl()).willReturn(Duration.ofHours(1));
        given(jwtTokenProvider.refreshTokenTtl()).willReturn(Duration.ofDays(14));
    }

    private User userWithId(long id) {
        User u = User.create(AuthProvider.KAKAO, "kakao-id-" + id, "u@example.com", "tester");
        ReflectionTestUtils.setField(u, "id", id);
        return u;
    }

    @Test
    void kakaoLogin_provisions_new_user_when_none_exists() {
        given(kakaoTokenVerifier.verifyAndFetch("kakao-AT"))
                .willReturn(new KakaoUser("kakao-id-200", "u@example.com", "tester"));
        given(userRepository.findByProviderAndProviderUserId(AuthProvider.KAKAO, "kakao-id-200"))
                .willReturn(Optional.empty());
        User saved = userWithId(200L);
        given(userRepository.save(any(User.class))).willReturn(saved);

        AuthTokens tokens = service.kakaoLogin("kakao-AT");

        verify(userRepository).save(any(User.class));
        verify(refreshTokenRepository).save(any(RefreshToken.class));
        assertThat(tokens.userId()).isEqualTo(200L);
        assertThat(tokens.accessToken()).isEqualTo("AT");
        assertThat(tokens.refreshToken()).isEqualTo("RT-raw");
    }

    @Test
    void kakaoLogin_updates_profile_for_existing_user() {
        User existing = userWithId(200L);
        given(kakaoTokenVerifier.verifyAndFetch("kakao-AT"))
                .willReturn(new KakaoUser("kakao-id-200", "new@example.com", "newnick"));
        given(userRepository.findByProviderAndProviderUserId(AuthProvider.KAKAO, "kakao-id-200"))
                .willReturn(Optional.of(existing));

        AuthTokens tokens = service.kakaoLogin("kakao-AT");

        assertThat(existing.getEmail()).isEqualTo("new@example.com");
        assertThat(existing.getNickname()).isEqualTo("newnick");
        verify(userRepository, never()).save(any(User.class));
        assertThat(tokens.userId()).isEqualTo(200L);
    }

    @Test
    void kakaoLogin_throws_when_existing_user_already_withdrawn() {
        User withdrawn = userWithId(200L);
        withdrawn.withdraw();
        given(kakaoTokenVerifier.verifyAndFetch("kakao-AT"))
                .willReturn(new KakaoUser("kakao-id-200", null, null));
        given(userRepository.findByProviderAndProviderUserId(AuthProvider.KAKAO, "kakao-id-200"))
                .willReturn(Optional.of(withdrawn));

        assertThatThrownBy(() -> service.kakaoLogin("kakao-AT"))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.USER_ALREADY_WITHDRAWN);
    }

    @Test
    void refresh_unknown_token_throws() {
        given(jwtTokenProvider.hash("missing")).willReturn("hash-missing");
        given(refreshTokenRepository.findByTokenHash("hash-missing")).willReturn(Optional.empty());

        assertThatThrownBy(() -> service.refresh("missing"))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AUTH_REFRESH_TOKEN_INVALID);
    }

    @Test
    void refresh_revoked_token_throws() {
        User user = userWithId(200L);
        RefreshToken rt = RefreshToken.issue(user, "hash-old", LocalDateTime.now().plusDays(7));
        rt.revoke();
        given(jwtTokenProvider.hash("old-raw")).willReturn("hash-old");
        given(refreshTokenRepository.findByTokenHash("hash-old")).willReturn(Optional.of(rt));

        assertThatThrownBy(() -> service.refresh("old-raw"))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AUTH_REFRESH_TOKEN_INVALID);
    }

    @Test
    void refresh_expired_token_throws() {
        User user = userWithId(200L);
        RefreshToken rt = RefreshToken.issue(user, "hash-old", LocalDateTime.now().minusMinutes(1));
        given(jwtTokenProvider.hash("old-raw")).willReturn("hash-old");
        given(refreshTokenRepository.findByTokenHash("hash-old")).willReturn(Optional.of(rt));

        assertThatThrownBy(() -> service.refresh("old-raw"))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AUTH_REFRESH_TOKEN_INVALID);
    }

    @Test
    void refresh_rotates_token_on_success() {
        User user = userWithId(200L);
        RefreshToken rt = RefreshToken.issue(user, "hash-old", LocalDateTime.now().plusDays(7));
        given(jwtTokenProvider.hash("old-raw")).willReturn("hash-old");
        given(refreshTokenRepository.findByTokenHash("hash-old")).willReturn(Optional.of(rt));

        AuthTokens tokens = service.refresh("old-raw");

        assertThat(rt.isRevoked()).isTrue();
        verify(refreshTokenRepository).save(any(RefreshToken.class));
        assertThat(tokens.accessToken()).isEqualTo("AT");
        assertThat(tokens.refreshToken()).isEqualTo("RT-raw");
        assertThat(tokens.userId()).isEqualTo(200L);
    }

    @Test
    void refresh_throws_when_user_already_withdrawn() {
        User user = userWithId(200L);
        user.withdraw();
        RefreshToken rt = RefreshToken.issue(user, "hash-old", LocalDateTime.now().plusDays(7));
        given(jwtTokenProvider.hash("old-raw")).willReturn("hash-old");
        given(refreshTokenRepository.findByTokenHash("hash-old")).willReturn(Optional.of(rt));

        assertThatThrownBy(() -> service.refresh("old-raw"))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.USER_ALREADY_WITHDRAWN);
    }

    @Test
    void logout_revokes_all_user_refresh_tokens() {
        service.logout(200L);
        verify(refreshTokenRepository).revokeAllByUserId(200L);
    }
}
