package com.hjson.tenk.domain.amount;

import com.hjson.tenk.common.api.ApiResponse;
import com.hjson.tenk.domain.amount.dto.AmountCreateRequest;
import com.hjson.tenk.domain.amount.dto.AmountResponse;
import com.hjson.tenk.security.CurrentUserId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Encoding;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.parameters.RequestBody;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@Tag(name = "Amount", description = "지출/무지출 기록 API")
@RestController
@RequestMapping("/api/challenges/{challengeId}/amounts")
@RequiredArgsConstructor
public class AmountController {

    private final AmountService amountService;

    @Operation(summary = "지출/무지출 기록 추가 (지출은 영상 필수, 무지출은 영상 선택)")
    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequestBody(content = @Content(
            mediaType = MediaType.MULTIPART_FORM_DATA_VALUE,
            schema = @Schema(implementation = AmountCreateRequest.class),
            encoding = {
                    @Encoding(name = "request", contentType = MediaType.APPLICATION_JSON_VALUE),
                    @Encoding(name = "video", contentType = "video/*")
            }
    ))
    public ApiResponse<AmountResponse> record(@CurrentUserId Long userId,
                                              @PathVariable Long challengeId,
                                              @RequestPart("request") AmountCreateRequest request,
                                              @RequestPart(value = "video", required = false) MultipartFile video) {
        return ApiResponse.ok(amountService.record(userId, challengeId, request, video));
    }

    @Operation(summary = "챌린지 별 지출 목록")
    @GetMapping
    public ApiResponse<List<AmountResponse>> list(@CurrentUserId Long userId,
                                                  @PathVariable Long challengeId) {
        return ApiResponse.ok(amountService.listByChallenge(userId, challengeId));
    }

    @Operation(summary = "지출 기록 삭제")
    @DeleteMapping("/{amountId}")
    public ApiResponse<Void> delete(@CurrentUserId Long userId,
                                    @PathVariable Long challengeId,
                                    @PathVariable Long amountId) {
        amountService.delete(userId, challengeId, amountId);
        return ApiResponse.ok();
    }
}
