package com.hjson.tenk.domain.user;

import com.hjson.tenk.common.api.ApiResponse;
import com.hjson.tenk.domain.user.dto.NicknameUpdateRequest;
import com.hjson.tenk.domain.user.dto.UserResponse;
import com.hjson.tenk.security.CurrentUserId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "User", description = "사용자 API")
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @Operation(summary = "내 정보 조회")
    @GetMapping("/me")
    public ApiResponse<UserResponse> me(@CurrentUserId Long userId) {
        return ApiResponse.ok(UserResponse.from(userService.getActiveUser(userId)));
    }

    @Operation(summary = "닉네임 수정")
    @PatchMapping("/me/nickname")
    public ApiResponse<UserResponse> updateNickname(@CurrentUserId Long userId,
                                                    @Valid @RequestBody NicknameUpdateRequest request) {
        userService.updateNickname(userId, request.nickname());
        return ApiResponse.ok(UserResponse.from(userService.getActiveUser(userId)));
    }

    @Operation(summary = "회원 탈퇴(소프트 딜리트) — 모든 RT가 함께 무효화됨")
    @DeleteMapping("/me")
    public ApiResponse<Void> withdraw(@CurrentUserId Long userId) {
        userService.withdraw(userId);
        return ApiResponse.ok();
    }
}
