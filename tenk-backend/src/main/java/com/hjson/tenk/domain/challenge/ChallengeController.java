package com.hjson.tenk.domain.challenge;

import com.hjson.tenk.common.api.ApiResponse;
import com.hjson.tenk.domain.challenge.dto.ChallengeCreateRequest;
import com.hjson.tenk.domain.challenge.dto.ChallengeExportResponse;
import com.hjson.tenk.domain.challenge.dto.ChallengeResponse;
import com.hjson.tenk.security.CurrentUserId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "Challenge", description = "챌린지 API")
@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class ChallengeController {

    private final ChallengeService challengeService;
    private final ChallengeExportService challengeExportService;

    @Operation(summary = "챌린지 생성 (최대 7일)")
    @PostMapping
    public ApiResponse<ChallengeResponse> create(@CurrentUserId Long userId,
                                                 @Valid @RequestBody ChallengeCreateRequest request) {
        return ApiResponse.ok(challengeService.create(userId, request));
    }

    @Operation(summary = "내 챌린지 목록")
    @GetMapping
    public ApiResponse<List<ChallengeResponse>> list(@CurrentUserId Long userId,
                                                     @RequestParam(defaultValue = "false") boolean activeOnly) {
        return ApiResponse.ok(challengeService.listMine(userId, activeOnly));
    }

    @Operation(summary = "챌린지 단건 조회 (잔액 포함)")
    @GetMapping("/{challengeId}")
    public ApiResponse<ChallengeResponse> get(@CurrentUserId Long userId,
                                              @PathVariable Long challengeId) {
        return ApiResponse.ok(challengeService.getOne(userId, challengeId));
    }

    @Operation(summary = "챌린지 결과 확정 (종료된 챌린지 대상)")
    @PostMapping("/{challengeId}/finalize")
    public ApiResponse<ChallengeResponse> finalizeChallenge(@CurrentUserId Long userId,
                                                            @PathVariable Long challengeId) {
        return ApiResponse.ok(challengeService.finalizeIfDue(userId, challengeId));
    }

    @Operation(summary = "챌린지 결과 내보내기 (JSON)")
    @GetMapping("/{challengeId}/export")
    public ApiResponse<ChallengeExportResponse> export(@CurrentUserId Long userId,
                                                       @PathVariable Long challengeId) {
        return ApiResponse.ok(challengeExportService.export(userId, challengeId));
    }

    @Operation(summary = "챌린지 삭제 (소프트 딜리트)")
    @DeleteMapping("/{challengeId}")
    public ApiResponse<Void> delete(@CurrentUserId Long userId,
                                    @PathVariable Long challengeId) {
        challengeService.delete(userId, challengeId);
        return ApiResponse.ok();
    }
}
