package com.hjson.tenk.domain.amount;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.challenge.Challenge;
import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class AmountTest {

    private final User user = User.create(AuthProvider.KAKAO, "kakao-1", "u@example.com", "tester");

    private Challenge fiveDayChallenge() {
        LocalDate today = LocalDate.now();
        return Challenge.create(user, today, today.plusDays(4), 10_000);
    }

    @Test
    void spend_amount_must_be_positive() {
        Challenge c = fiveDayChallenge();
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 0, LocalDateTime.now()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", -1, LocalDateTime.now()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
    }

    @Test
    void spend_requires_category_and_content() {
        Challenge c = fiveDayChallenge();
        LocalDateTime now = LocalDateTime.now();
        assertThatThrownBy(() -> Amount.spend(c, null, "lunch", 1_000, now))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
        assertThatThrownBy(() -> Amount.spend(c, "food", "  ", 1_000, now))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
    }

    @Test
    void spend_date_out_of_challenge_range_throws() {
        Challenge c = fiveDayChallenge();
        LocalDateTime beforeStart = c.getStartDate().minusDays(1).atTime(12, 0);
        LocalDateTime afterEnd = c.getEndDate().plusDays(1).atTime(12, 0);
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 1_000, beforeStart))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 1_000, afterEnd))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
    }

    @Test
    void spend_null_date_throws() {
        Challenge c = fiveDayChallenge();
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 1_000, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
    }

    @Test
    void spend_happy_path_sets_fields() {
        Challenge c = fiveDayChallenge();
        LocalDateTime when = c.getStartDate().atTime(9, 30);
        Amount a = Amount.spend(c, "food", "lunch", 5_000, when);
        assertThat(a.getCategory()).isEqualTo("food");
        assertThat(a.getContent()).isEqualTo("lunch");
        assertThat(a.getAmount()).isEqualTo(5_000);
        assertThat(a.isNoSpend()).isFalse();
        assertThat(a.getSpentDt()).isEqualTo(when);
    }

    @Test
    void noSpend_allows_null_category_and_zero_amount() {
        Challenge c = fiveDayChallenge();
        Amount a = Amount.noSpend(c, c.getStartDate().atTime(20, 0));
        assertThat(a.isNoSpend()).isTrue();
        assertThat(a.getAmount()).isZero();
        assertThat(a.getCategory()).isNull();
        assertThat(a.getContent()).isNull();
    }

    @Test
    void noSpend_date_out_of_range_throws() {
        Challenge c = fiveDayChallenge();
        assertThatThrownBy(() -> Amount.noSpend(c, c.getEndDate().plusDays(1).atTime(0, 0)))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
    }

    @Test
    void update_on_noSpend_must_keep_amount_zero() {
        Challenge c = fiveDayChallenge();
        Amount a = Amount.noSpend(c, c.getStartDate().atTime(20, 0));
        assertThatThrownBy(() -> a.update(null, null, 500))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_NO_SPEND_VALUE);
        a.update("ignored", "ignored", 0);
        assertThat(a.getCategory()).isNull();
        assertThat(a.getContent()).isNull();
        assertThat(a.getAmount()).isZero();
    }

    @Test
    void update_on_spend_validates_positive_and_fields() {
        Challenge c = fiveDayChallenge();
        Amount a = Amount.spend(c, "food", "lunch", 5_000, c.getStartDate().atTime(9, 0));
        assertThatThrownBy(() -> a.update("food", "dinner", 0))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
        assertThatThrownBy(() -> a.update("", "dinner", 1_000))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
        a.update("food", "dinner", 7_000);
        assertThat(a.getContent()).isEqualTo("dinner");
        assertThat(a.getAmount()).isEqualTo(7_000);
    }
}
