package com.hjson.tenk.domain.challenge;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class ChallengeTest {

    private final User user = User.create(AuthProvider.KAKAO, "kakao-1", "u@example.com", "tester");

    @Test
    void create_today_to_29days_inclusive_is_30_days_and_passes() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today, today.plusDays(29), 10_000);
        assertThat(c.getStartDate()).isEqualTo(today);
        assertThat(c.getEndDate()).isEqualTo(today.plusDays(29));
    }

    @Test
    void create_31_days_throws_period_invalid() {
        LocalDate today = LocalDate.now();
        assertThatThrownBy(() -> Challenge.create(user, today, today.plusDays(30), 10_000))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_PERIOD_INVALID);
    }

    @Test
    void create_start_date_in_past_throws() {
        LocalDate today = LocalDate.now();
        assertThatThrownBy(() -> Challenge.create(user, today.minusDays(1), today.plusDays(5), 10_000))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_PERIOD_INVALID);
    }

    @Test
    void create_end_before_start_throws() {
        LocalDate today = LocalDate.now();
        assertThatThrownBy(() -> Challenge.create(user, today.plusDays(5), today.plusDays(3), 10_000))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_PERIOD_INVALID);
    }

    @Test
    void create_null_dates_throw() {
        LocalDate today = LocalDate.now();
        assertThatThrownBy(() -> Challenge.create(user, null, today, 10_000))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_PERIOD_INVALID);
        assertThatThrownBy(() -> Challenge.create(user, today, null, 10_000))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_PERIOD_INVALID);
    }

    @Test
    void isStarted_returns_false_before_start_date_and_true_on_and_after() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today.plusDays(2), today.plusDays(5), 10_000);
        assertThat(c.isStarted(today.plusDays(1))).isFalse();
        assertThat(c.isStarted(today.plusDays(2))).isTrue();
        assertThat(c.isStarted(today.plusDays(3))).isTrue();
    }

    @Test
    void isFinished_returns_false_on_end_date_and_true_after() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today, today.plusDays(3), 10_000);
        assertThat(c.isFinished(today.plusDays(3))).isFalse();
        assertThat(c.isFinished(today.plusDays(4))).isTrue();
    }

    @Test
    void containsDate_inclusive_both_ends() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today, today.plusDays(3), 10_000);
        assertThat(c.containsDate(today.minusDays(1))).isFalse();
        assertThat(c.containsDate(today)).isTrue();
        assertThat(c.containsDate(today.plusDays(3))).isTrue();
        assertThat(c.containsDate(today.plusDays(4))).isFalse();
    }

    @Test
    void markResult_twice_throws_already_finished() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today, today.plusDays(1), 10_000);
        c.markResult(ChallengeResult.SUCCESS);
        assertThatThrownBy(() -> c.markResult(ChallengeResult.FAIL))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_ALREADY_FINISHED);
    }

    @Test
    void softDelete_sets_flag_and_timestamp() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today, today.plusDays(1), 10_000);
        assertThat(c.isDeleted()).isFalse();
        c.softDelete();
        assertThat(c.isDeleted()).isTrue();
        assertThat(c.getDeletedDt()).isNotNull();
    }
}
