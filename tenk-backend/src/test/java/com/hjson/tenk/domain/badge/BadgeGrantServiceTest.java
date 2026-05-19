package com.hjson.tenk.domain.badge;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.hjson.tenk.domain.amount.Amount;
import com.hjson.tenk.domain.amount.AmountRepository;
import com.hjson.tenk.domain.challenge.Challenge;
import com.hjson.tenk.domain.challenge.ChallengeResult;
import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;
import com.hjson.tenk.domain.user.UserRepository;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class BadgeGrantServiceTest {

    @Mock AmountRepository amountRepository;
    @Mock BadgeRepository badgeRepository;
    @Mock UserBadgeRepository userBadgeRepository;
    @Mock UserRepository userRepository;

    @InjectMocks BadgeGrantService service;

    private static final LocalDate TODAY = LocalDate.now();

    private User user;
    private Challenge bigChallenge;
    private Badge streak3, streak7, streak14, streak30;
    private Badge noSpend3, noSpend7, noSpend14, noSpend30;
    private Badge challengeSuccess1;

    @BeforeEach
    void setUp() {
        user = User.create(AuthProvider.KAKAO, "kakao-1", "u@example.com", "tester");
        ReflectionTestUtils.setField(user, "id", 100L);
        given(userRepository.findByIdAndDeletedFalse(100L)).willReturn(Optional.of(user));

        bigChallenge = Challenge.create(user, TODAY, TODAY, 1_000_000);
        ReflectionTestUtils.setField(bigChallenge, "startDate", TODAY.minusDays(70));
        ReflectionTestUtils.setField(bigChallenge, "endDate", TODAY.plusDays(1));

        streak3 = badge(BadgeType.STREAK, 3, 1L);
        streak7 = badge(BadgeType.STREAK, 7, 2L);
        streak14 = badge(BadgeType.STREAK, 14, 3L);
        streak30 = badge(BadgeType.STREAK, 30, 4L);
        noSpend3 = badge(BadgeType.NO_SPEND, 3, 5L);
        noSpend7 = badge(BadgeType.NO_SPEND, 7, 6L);
        noSpend14 = badge(BadgeType.NO_SPEND, 14, 7L);
        noSpend30 = badge(BadgeType.NO_SPEND, 30, 8L);
        challengeSuccess1 = badge(BadgeType.CHALLENGE_SUCCESS, 1, 9L);

        given(badgeRepository.findByTypeOrderByConditionValueAsc(BadgeType.STREAK))
                .willReturn(List.of(streak3, streak7, streak14, streak30));
        given(badgeRepository.findByTypeOrderByConditionValueAsc(BadgeType.NO_SPEND))
                .willReturn(List.of(noSpend3, noSpend7, noSpend14, noSpend30));
        given(badgeRepository.findByTypeAndConditionValue(BadgeType.CHALLENGE_SUCCESS, 1))
                .willReturn(Optional.of(challengeSuccess1));
    }

    private Badge badge(BadgeType type, int value, long id) {
        Badge b = new Badge();
        ReflectionTestUtils.setField(b, "id", id);
        ReflectionTestUtils.setField(b, "type", type);
        ReflectionTestUtils.setField(b, "conditionValue", value);
        ReflectionTestUtils.setField(b, "iconPath", "icon-" + type + "-" + value + ".png");
        return b;
    }

    private Amount spendOn(LocalDate day) {
        return Amount.spend(bigChallenge, "x", "x", 100, day.atTime(12, 0));
    }

    private Amount noSpendOn(LocalDate day) {
        return Amount.noSpend(bigChallenge, day.atTime(12, 0));
    }

    private void stubAmounts(List<Amount> records) {
        given(amountRepository.findUserAmountsBetween(eq(100L), any(LocalDateTime.class), any(LocalDateTime.class)))
                .willReturn(records);
    }

    @Test
    void streak_three_consecutive_days_grants_streak_3_only() {
        stubAmounts(List.of(
                spendOn(TODAY.minusDays(2)),
                spendOn(TODAY.minusDays(1)),
                spendOn(TODAY)
        ));

        service.evaluateForUser(100L);

        verify(userBadgeRepository).existsByUserAndBadge(user, streak3);
        verify(userBadgeRepository, never()).existsByUserAndBadge(user, streak7);
        verify(userBadgeRepository, times(1)).save(any(UserBadge.class));
    }

    @Test
    void streak_falls_back_to_yesterday_when_today_missing() {
        // 어제~어제-4 까지 5일 연속 — 오늘 미기록이라도 어제 기준으로 5일 streak
        stubAmounts(List.of(
                spendOn(TODAY.minusDays(5)),
                spendOn(TODAY.minusDays(4)),
                spendOn(TODAY.minusDays(3)),
                spendOn(TODAY.minusDays(2)),
                spendOn(TODAY.minusDays(1))
        ));

        service.evaluateForUser(100L);

        verify(userBadgeRepository).existsByUserAndBadge(user, streak3);
        verify(userBadgeRepository, never()).existsByUserAndBadge(user, streak7);
        verify(userBadgeRepository, times(1)).save(any(UserBadge.class));
    }

    @Test
    void streak_broken_when_yesterday_missing_grants_nothing() {
        // 그제까지만 기록 — 어제도 오늘도 비어있어 streak = 0
        stubAmounts(List.of(
                spendOn(TODAY.minusDays(3)),
                spendOn(TODAY.minusDays(2))
        ));

        service.evaluateForUser(100L);

        verify(userBadgeRepository, never()).save(any());
    }

    @Test
    void no_spend_streak_breaks_when_spend_record_intrudes() {
        // 오늘/어제/그제 모두 무지출이지만 그제에 지출도 함께 기록 → 그날 NO_SPEND 자격 박탈, STREAK는 살아남음
        stubAmounts(List.of(
                noSpendOn(TODAY.minusDays(2)),
                spendOn(TODAY.minusDays(2)),
                noSpendOn(TODAY.minusDays(1)),
                noSpendOn(TODAY)
        ));

        service.evaluateForUser(100L);

        // STREAK: 3일 연속 어떤 기록이라도 있음 → STREAK 3 지급
        verify(userBadgeRepository).existsByUserAndBadge(user, streak3);
        // NO_SPEND: 그제는 지출이 끼어 무지출-only 아님. 오늘+어제 = 2일 → NO_SPEND 3 미달, 지급 안 함
        verify(userBadgeRepository, never()).existsByUserAndBadge(user, noSpend3);
    }

    @Test
    void already_granted_badge_is_not_saved_twice() {
        stubAmounts(List.of(
                spendOn(TODAY.minusDays(2)),
                spendOn(TODAY.minusDays(1)),
                spendOn(TODAY)
        ));
        given(userBadgeRepository.existsByUserAndBadge(user, streak3)).willReturn(true);

        service.evaluateForUser(100L);

        verify(userBadgeRepository, never()).save(any());
    }

    @Test
    void grant_challenge_success_only_on_success_result() {
        service.grantChallengeSuccess(100L, ChallengeResult.SUCCESS);
        verify(userBadgeRepository).existsByUserAndBadge(user, challengeSuccess1);
        verify(userBadgeRepository).save(any(UserBadge.class));
    }

    @Test
    void grant_challenge_success_does_nothing_on_fail() {
        service.grantChallengeSuccess(100L, ChallengeResult.FAIL);
        verifyNoInteractions(badgeRepository);
        verifyNoInteractions(userBadgeRepository);
    }

    @Test
    void evaluate_for_missing_user_does_nothing() {
        given(userRepository.findByIdAndDeletedFalse(999L)).willReturn(Optional.empty());
        service.evaluateForUser(999L);
        verifyNoInteractions(amountRepository);
        verifyNoInteractions(badgeRepository);
        verifyNoInteractions(userBadgeRepository);
    }
}
