package com.hjson.tenk.domain.challenge.dto;

import com.hjson.tenk.domain.challenge.ChallengeResult;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

public record ChallengeExportResponse(
        Long challengeId,
        LocalDateTime startDt,
        LocalDateTime endDt,
        int targetAmount,
        long totalSpent,
        long balance,
        ChallengeResult result,
        List<DailySummary> dailySummary,
        List<CategorySummary> categorySummary,
        List<AmountItem> amounts
) {
    public record DailySummary(LocalDate date, long total, boolean noSpendDay) {}
    public record CategorySummary(String category, long total) {}
    public record AmountItem(Long amountId,
                             LocalDateTime createdDt,
                             String category,
                             String content,
                             int amount,
                             boolean noSpend,
                             List<Long> mediaFileIds) {}
}
