package com.hjson.tenk.domain.challenge;

import com.hjson.tenk.domain.amount.Amount;
import com.hjson.tenk.domain.amount.AmountRepository;
import com.hjson.tenk.domain.challenge.dto.ChallengeExportResponse;
import com.hjson.tenk.domain.challenge.dto.ChallengeExportResponse.AmountItem;
import com.hjson.tenk.domain.challenge.dto.ChallengeExportResponse.CategorySummary;
import com.hjson.tenk.domain.challenge.dto.ChallengeExportResponse.DailySummary;
import com.hjson.tenk.domain.media.MediaFile;
import com.hjson.tenk.domain.media.MediaFileRepository;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ChallengeExportService {

    private final ChallengeService challengeService;
    private final AmountRepository amountRepository;
    private final MediaFileRepository mediaFileRepository;

    public ChallengeExportResponse export(Long userId, Long challengeId) {
        Challenge challenge = challengeService.loadOwned(userId, challengeId);
        List<Amount> amounts = amountRepository.findByChallengeOrderByCreatedDtAsc(challenge);

        long totalSpent = amounts.stream().mapToLong(Amount::getAmount).sum();

        Map<LocalDate, long[]> perDay = new TreeMap<>();
        Map<String, Long> perCategory = new LinkedHashMap<>();
        List<AmountItem> items = amounts.stream()
                .map(a -> {
                    LocalDate day = a.getCreatedDt().toLocalDate();
                    long[] bucket = perDay.computeIfAbsent(day, d -> new long[]{0, 1});
                    bucket[0] += a.getAmount();
                    if (!a.isNoSpend()) bucket[1] = 0;
                    if (!a.isNoSpend() && a.getCategory() != null) {
                        perCategory.merge(a.getCategory(), (long) a.getAmount(), Long::sum);
                    }
                    List<Long> mediaIds = mediaFileRepository.findByAmount(a).stream()
                            .map(MediaFile::getId).toList();
                    return new AmountItem(a.getId(), a.getCreatedDt(), a.getCategory(),
                            a.getContent(), a.getAmount(), a.isNoSpend(), mediaIds);
                })
                .toList();

        List<DailySummary> daily = perDay.entrySet().stream()
                .map(e -> new DailySummary(e.getKey(), e.getValue()[0], e.getValue()[1] == 1))
                .toList();

        List<CategorySummary> categories = perCategory.entrySet().stream()
                .map(e -> new CategorySummary(e.getKey(), e.getValue()))
                .sorted(Comparator.comparingLong(CategorySummary::total).reversed())
                .toList();

        return new ChallengeExportResponse(
                challenge.getId(),
                challenge.getStartDt(),
                challenge.getEndDt(),
                challenge.getTargetAmount(),
                totalSpent,
                challenge.getTargetAmount() - totalSpent,
                challenge.getResult(),
                daily,
                categories,
                items);
    }
}
