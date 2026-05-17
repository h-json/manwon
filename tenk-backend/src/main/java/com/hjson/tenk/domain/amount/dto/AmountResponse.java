package com.hjson.tenk.domain.amount.dto;

import com.hjson.tenk.domain.amount.Amount;
import com.hjson.tenk.domain.media.MediaFile;
import java.time.LocalDateTime;
import java.util.List;

public record AmountResponse(
        Long amountId,
        Long challengeId,
        String category,
        String content,
        int amount,
        boolean noSpend,
        LocalDateTime createdDt,
        List<MediaFileSummary> mediaFiles
) {
    public static AmountResponse of(Amount amount, List<MediaFile> mediaFiles) {
        return new AmountResponse(
                amount.getId(),
                amount.getChallenge().getId(),
                amount.getCategory(),
                amount.getContent(),
                amount.getAmount(),
                amount.isNoSpend(),
                amount.getCreatedDt(),
                mediaFiles.stream().map(MediaFileSummary::from).toList()
        );
    }

    public record MediaFileSummary(Long fileId, String filePath, String originalName) {
        public static MediaFileSummary from(MediaFile mediaFile) {
            return new MediaFileSummary(mediaFile.getId(), mediaFile.getFilePath(), mediaFile.getOriginalName());
        }
    }
}
