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
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 0, null, LocalDateTime.now()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", -1, null, LocalDateTime.now()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
    }

    @Test
    void spend_requires_category_and_content() {
        Challenge c = fiveDayChallenge();
        LocalDateTime now = LocalDateTime.now();
        assertThatThrownBy(() -> Amount.spend(c, null, "lunch", 1_000, null, now))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
        assertThatThrownBy(() -> Amount.spend(c, "food", "  ", 1_000, null, now))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
    }

    @Test
    void spend_date_out_of_challenge_range_throws() {
        Challenge c = fiveDayChallenge();
        LocalDateTime beforeStart = c.getStartDate().minusDays(1).atTime(12, 0);
        LocalDateTime afterEnd = c.getEndDate().plusDays(1).atTime(12, 0);
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 1_000, null, beforeStart))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 1_000, null, afterEnd))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
    }

    @Test
    void spend_null_date_throws() {
        Challenge c = fiveDayChallenge();
        assertThatThrownBy(() -> Amount.spend(c, "food", "lunch", 1_000, null, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
    }

    @Test
    void spend_happy_path_sets_fields() {
        Challenge c = fiveDayChallenge();
        LocalDateTime when = c.getStartDate().atTime(9, 30);
        Amount a = Amount.spend(c, "food", "lunch", 5_000, "회식 핑계", when);
        assertThat(a.getCategory()).isEqualTo("food");
        assertThat(a.getContent()).isEqualTo("lunch");
        assertThat(a.getAmount()).isEqualTo(5_000);
        assertThat(a.isNoSpend()).isFalse();
        assertThat(a.getMemo()).isEqualTo("회식 핑계");
        assertThat(a.getSpentDt()).isEqualTo(when);
    }

    @Test
    void spend_blank_memo_is_normalized_to_null() {
        Challenge c = fiveDayChallenge();
        Amount a = Amount.spend(c, "food", "lunch", 5_000, "   ", c.getStartDate().atTime(9, 0));
        assertThat(a.getMemo()).isNull();
    }

    @Test
    void noSpend_allows_null_category_and_zero_amount() {
        Challenge c = fiveDayChallenge();
        Amount a = Amount.noSpend(c, null, c.getStartDate().atTime(20, 0));
        assertThat(a.isNoSpend()).isTrue();
        assertThat(a.getAmount()).isZero();
        assertThat(a.getCategory()).isNull();
        assertThat(a.getContent()).isNull();
        assertThat(a.getMemo()).isNull();
    }

    @Test
    void noSpend_keeps_memo() {
        Challenge c = fiveDayChallenge();
        Amount a = Amount.noSpend(c, "오늘 잘 참았다", c.getStartDate().atTime(20, 0));
        assertThat(a.getMemo()).isEqualTo("오늘 잘 참았다");
    }

    @Test
    void noSpend_date_out_of_range_throws() {
        Challenge c = fiveDayChallenge();
        assertThatThrownBy(() -> Amount.noSpend(c, null, c.getEndDate().plusDays(1).atTime(0, 0)))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
    }

    @Test
    void update_on_noSpend_must_keep_amount_zero() {
        Challenge c = fiveDayChallenge();
        LocalDateTime original = c.getStartDate().atTime(20, 0);
        Amount a = Amount.noSpend(c, null, original);
        // spentDt 인자는 무지출에서 무시되더라도 시그니처 통과시켜야 한다.
        assertThatThrownBy(() -> a.update(null, null, 500, null, original))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_NO_SPEND_VALUE);
        // 인자로 다른 일시를 박아도 무지출은 spentDt 를 갱신하지 않는다.
        LocalDateTime ignoredNew = c.getEndDate().atTime(23, 0);
        a.update("ignored", "ignored", 0, "수정된 메모", ignoredNew);
        assertThat(a.getCategory()).isNull();
        assertThat(a.getContent()).isNull();
        assertThat(a.getAmount()).isZero();
        assertThat(a.getMemo()).isEqualTo("수정된 메모");
        assertThat(a.getSpentDt()).isEqualTo(original);
    }

    @Test
    void update_on_spend_validates_positive_and_fields() {
        Challenge c = fiveDayChallenge();
        LocalDateTime when = c.getStartDate().atTime(9, 0);
        Amount a = Amount.spend(c, "food", "lunch", 5_000, null, when);
        assertThatThrownBy(() -> a.update("food", "dinner", 0, null, when))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
        assertThatThrownBy(() -> a.update("", "dinner", 1_000, null, when))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
        a.update("food", "dinner", 7_000, "야근", when);
        assertThat(a.getContent()).isEqualTo("dinner");
        assertThat(a.getAmount()).isEqualTo(7_000);
        assertThat(a.getMemo()).isEqualTo("야근");
    }

    @Test
    void update_on_spend_can_change_spent_dt_within_range() {
        Challenge c = fiveDayChallenge();
        LocalDateTime original = c.getStartDate().atTime(9, 0);
        Amount a = Amount.spend(c, "food", "lunch", 5_000, null, original);
        LocalDateTime laterSameRange = c.getStartDate().plusDays(1).atTime(22, 30);
        a.update("food", "lunch", 5_000, null, laterSameRange);
        assertThat(a.getSpentDt()).isEqualTo(laterSameRange);
    }

    @Test
    void update_on_spend_rejects_spent_dt_out_of_range() {
        Challenge c = fiveDayChallenge();
        Amount a = Amount.spend(c, "food", "lunch", 5_000, null, c.getStartDate().atTime(9, 0));
        LocalDateTime afterEnd = c.getEndDate().plusDays(1).atTime(0, 0);
        assertThatThrownBy(() -> a.update("food", "lunch", 5_000, null, afterEnd))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
    }
}
