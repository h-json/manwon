package com.hjson.tenk.domain.badge;

import com.hjson.tenk.domain.amount.Amount;
import com.hjson.tenk.domain.amount.AmountRepository;
import com.hjson.tenk.domain.challenge.ChallengeResult;
import com.hjson.tenk.domain.user.User;
import com.hjson.tenk.domain.user.UserRepository;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 배지 지급 정책
 *  - STREAK : 매일(지출+무지출 포함) 기록한 연속 일수
 *  - NO_SPEND : "지출 0원" 기록만 연속된 일수 (지출 기록이 끼면 끊김)
 *  - CHALLENGE_SUCCESS : 챌린지가 성공으로 확정될 때 1회 지급
 *  단계 (condition_value): 3 / 7 / 14 / 30
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class BadgeGrantService {

    private static final int LOOKBACK_DAYS = 60;

    private final AmountRepository amountRepository;
    private final BadgeRepository badgeRepository;
    private final UserBadgeRepository userBadgeRepository;
    private final UserRepository userRepository;

    @Transactional
    public void evaluateForUser(Long userId) {
        User user = userRepository.findByIdAndDeletedFalse(userId).orElse(null);
        if (user == null) return;

        LocalDate today = LocalDate.now();
        LocalDateTime from = today.minusDays(LOOKBACK_DAYS).atStartOfDay();
        LocalDateTime to = today.plusDays(1).atStartOfDay();
        List<Amount> records = amountRepository.findUserAmountsBetween(user.getId(), from, to);

        Set<LocalDate> daysWithAnyRecord = new TreeSet<>();
        Set<LocalDate> daysWithOnlyNoSpend = new TreeSet<>();
        Set<LocalDate> daysWithSpend = new TreeSet<>();

        for (Amount a : records) {
            LocalDate day = a.getCreatedDt().toLocalDate();
            daysWithAnyRecord.add(day);
            if (a.isNoSpend()) {
                daysWithOnlyNoSpend.add(day);
            } else {
                daysWithSpend.add(day);
            }
        }
        daysWithOnlyNoSpend.removeAll(daysWithSpend);

        int streak = consecutiveStreakEndingOn(daysWithAnyRecord, today);
        int noSpendStreak = consecutiveStreakEndingOn(daysWithOnlyNoSpend, today);

        grantBadgesUpTo(user, BadgeType.STREAK, streak);
        grantBadgesUpTo(user, BadgeType.NO_SPEND, noSpendStreak);
    }

    @Transactional
    public void grantChallengeSuccess(Long userId, ChallengeResult result) {
        if (result != ChallengeResult.SUCCESS) return;
        userRepository.findByIdAndDeletedFalse(userId).ifPresent(user -> {
            badgeRepository.findByTypeAndConditionValue(BadgeType.CHALLENGE_SUCCESS, 1)
                    .ifPresent(badge -> grantIfAbsent(user, badge));
        });
    }

    @Transactional
    public void evaluateAllUsers() {
        userRepository.findAll().stream()
                .filter(u -> !u.isDeleted())
                .forEach(u -> {
                    try {
                        evaluateForUser(u.getId());
                    } catch (Exception e) {
                        log.warn("[Badge] evaluation failed userId={}", u.getId(), e);
                    }
                });
    }

    private void grantBadgesUpTo(User user, BadgeType type, int currentStreak) {
        if (currentStreak <= 0) return;
        List<Badge> ladder = badgeRepository.findByTypeOrderByConditionValueAsc(type);
        for (Badge badge : ladder) {
            if (currentStreak >= badge.getConditionValue()) {
                grantIfAbsent(user, badge);
            }
        }
    }

    private void grantIfAbsent(User user, Badge badge) {
        if (!userBadgeRepository.existsByUserAndBadge(user, badge)) {
            userBadgeRepository.save(UserBadge.create(user, badge));
            log.info("[Badge] granted userId={} badgeId={} type={} value={}",
                    user.getId(), badge.getId(), badge.getType(), badge.getConditionValue());
        }
    }

    private static int consecutiveStreakEndingOn(Set<LocalDate> days, LocalDate today) {
        if (days.isEmpty()) return 0;
        int streak = 0;
        LocalDate cursor = today;
        while (days.contains(cursor)) {
            streak++;
            cursor = cursor.minusDays(1);
        }
        if (streak == 0 && days.contains(today.minusDays(1))) {
            cursor = today.minusDays(1);
            while (days.contains(cursor)) {
                streak++;
                cursor = cursor.minusDays(1);
            }
        }
        return streak;
    }

    @SuppressWarnings("unused")
    private static LocalDateTime atEndOfDay(LocalDate date) {
        return date.atTime(LocalTime.MAX);
    }
}
