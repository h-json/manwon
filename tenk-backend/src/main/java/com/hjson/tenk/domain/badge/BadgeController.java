package com.hjson.tenk.domain.badge;

import com.hjson.tenk.common.api.ApiResponse;
import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.badge.dto.UserBadgeResponse;
import com.hjson.tenk.domain.user.User;
import com.hjson.tenk.domain.user.UserRepository;
import com.hjson.tenk.security.CurrentUserId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "Badge", description = "배지 API")
@RestController
@RequestMapping("/api/badges")
@RequiredArgsConstructor
public class BadgeController {

    private final UserBadgeRepository userBadgeRepository;
    private final UserRepository userRepository;

    @Operation(summary = "내가 획득한 배지 목록")
    @GetMapping("/me")
    public ApiResponse<List<UserBadgeResponse>> myBadges(@CurrentUserId Long userId) {
        User user = userRepository.findByIdAndDeletedFalse(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.USER_NOT_FOUND));
        return ApiResponse.ok(userBadgeRepository.findByUserOrderByCreatedDtDesc(user).stream()
                .map(UserBadgeResponse::from)
                .toList());
    }
}
