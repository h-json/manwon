package com.hjson.tenk.domain.amount.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalTime;

/**
 * 지출/무지출 기록 수정 요청.
 *
 * <p>일시 범위:
 * <ul>
 *   <li>지출: 날짜는 고정(기존 spentDt 의 LocalDate 유지). {@code time} 으로 시간만 변경.</li>
 *   <li>무지출: 일시 자체가 서버 now() 강제라 {@code time} 은 무시.</li>
 * </ul>
 *
 * <p>{@code videoAction}:
 * <ul>
 *   <li>{@link VideoAction#KEEP}: 기존 영상 유지 (video part 무시)</li>
 *   <li>{@link VideoAction#REMOVE}: 기존 영상 + 디스크 파일 삭제 (video part 무시)</li>
 *   <li>{@link VideoAction#REPLACE}: 기존 영상 삭제 후 새 video part 저장 (video part 필수)</li>
 * </ul>
 */
public record AmountUpdateRequest(
        String category,
        String content,
        Integer amount,
        @Size(max = 500) String memo,
        LocalTime time,
        @NotNull VideoAction videoAction
) {
    public enum VideoAction { KEEP, REMOVE, REPLACE }
}
