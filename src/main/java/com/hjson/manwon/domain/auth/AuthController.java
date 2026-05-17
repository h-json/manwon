package com.hjson.manwon.domain.auth;

import com.hjson.manwon.common.api.ApiResponse;
import com.hjson.manwon.domain.auth.dto.KakaoLoginRequest;
import com.hjson.manwon.domain.auth.dto.RefreshRequest;
import com.hjson.manwon.security.CurrentUserId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "Auth", description = "인증 API (모바일 카카오 SDK + 자체 JWT)")
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    @Operation(summary = "카카오 로그인",
            description = "모바일 SDK가 발급받은 카카오 access token으로 자체 JWT(AT/RT)를 발급한다.")
    @PostMapping("/kakao/login")
    public ApiResponse<AuthTokens> kakaoLogin(@Valid @RequestBody KakaoLoginRequest request) {
        return ApiResponse.ok(authService.kakaoLogin(request.accessToken()));
    }

    @Operation(summary = "토큰 갱신",
            description = "RT 한 번 사용 시 폐기되고 새 AT/RT가 발급된다 (rotation).")
    @PostMapping("/refresh")
    public ApiResponse<AuthTokens> refresh(@Valid @RequestBody RefreshRequest request) {
        return ApiResponse.ok(authService.refresh(request.refreshToken()));
    }

    @Operation(summary = "로그아웃", description = "해당 사용자의 모든 RT를 무효화한다.")
    @PostMapping("/logout")
    public ApiResponse<Void> logout(@CurrentUserId Long userId) {
        authService.logout(userId);
        return ApiResponse.ok();
    }
}
