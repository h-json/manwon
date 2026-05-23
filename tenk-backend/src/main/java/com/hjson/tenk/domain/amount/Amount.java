package com.hjson.tenk.domain.amount;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.challenge.Challenge;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EntityListeners;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

/**
 * 지출/무지출 기록.
 *
 * <p>날짜 의미 구분:
 * <ul>
 *   <li>{@code spentDt}: 사용자가 고른 "지출이 발생한 일시" (배지·집계의 기준 — 날짜만 추출해서 사용).
 *       날짜 부분은 챌린지 기간 안이어야 함.</li>
 *   <li>{@code createdDt}: 서버 자동 기록(JPA Auditing). 감사 용도이며 도메인 로직에서 직접 쓰지 않는다.</li>
 * </ul>
 */
@Getter
@Entity
@Table(name = "amount")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@EntityListeners(AuditingEntityListener.class)
public class Amount {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "amount_id")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "challenge_id", nullable = false)
    private Challenge challenge;

    @Column(name = "category", length = 255)
    private String category;

    @Column(name = "content", length = 255)
    private String content;

    @Column(name = "amount", nullable = false)
    private int amount;

    @Column(name = "is_no_spend", nullable = false)
    private boolean noSpend;

    /// 사용자가 기록 시 남기는 자유 메모. 영상 export 시 자막 디폴트를 오버라이드한다
    /// (메모 있으면 그 값, 없으면 지출="내용 금액원" / 무지출="무지출").
    @Column(name = "memo", length = 500)
    private String memo;

    @Column(name = "spent_dt", nullable = false)
    private LocalDateTime spentDt;

    @CreatedDate
    @Column(name = "created_dt", nullable = false, updatable = false)
    private LocalDateTime createdDt;

    /// "무지출 하루 1회" UNIQUE 인덱스를 받쳐주는 DB 생성 컬럼. JPA 는 읽기만 한다 (DDL 에서 GENERATED ALWAYS).
    /// 매핑이 빠지면 `ddl-auto=validate` 가 부팅 시점에 schema mismatch 로 막는다.
    @Column(name = "no_spend_day_key", insertable = false, updatable = false)
    private String noSpendDayKey;

    private Amount(Challenge challenge, String category, String content, int amount, boolean noSpend,
                   String memo, LocalDateTime spentDt) {
        this.challenge = challenge;
        this.category = category;
        this.content = content;
        this.amount = amount;
        this.noSpend = noSpend;
        this.memo = normalizeMemo(memo);
        this.spentDt = spentDt;
    }

    public static Amount spend(Challenge challenge, String category, String content, int amount,
                               String memo, LocalDateTime spentDt) {
        validateDateInChallenge(challenge, spentDt);
        if (amount <= 0) {
            throw new BusinessException(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
        }
        if (isBlank(category) || isBlank(content)) {
            throw new BusinessException(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
        }
        return new Amount(challenge, category, content, amount, false, memo, spentDt);
    }

    public static Amount noSpend(Challenge challenge, String memo, LocalDateTime spentDt) {
        validateDateInChallenge(challenge, spentDt);
        return new Amount(challenge, null, null, 0, true, memo, spentDt);
    }

    /// 지출/무지출 수정. {@code spentDt} 는 지출에만 적용 (무지출은 항상 서버 now() 강제라 인자 무시).
    /// 지출의 spentDt 는 날짜 부분이 챌린지 기간 안이어야 한다 — 시간만 바꿔도 검증을 다시 돈다.
    public void update(String category, String content, int amount, String memo,
                       LocalDateTime spentDt) {
        if (this.noSpend) {
            if (amount != 0) {
                throw new BusinessException(ErrorCode.AMOUNT_INVALID_NO_SPEND_VALUE);
            }
            this.category = null;
            this.content = null;
            this.amount = 0;
            this.memo = normalizeMemo(memo);
            return;
        }
        validateDateInChallenge(this.challenge, spentDt);
        if (amount <= 0) {
            throw new BusinessException(ErrorCode.AMOUNT_INVALID_SPEND_VALUE);
        }
        if (isBlank(category) || isBlank(content)) {
            throw new BusinessException(ErrorCode.AMOUNT_CATEGORY_CONTENT_REQUIRED);
        }
        this.category = category;
        this.content = content;
        this.amount = amount;
        this.memo = normalizeMemo(memo);
        this.spentDt = spentDt;
    }

    /// 빈/공백 메모는 null 로 정규화 — DTO 디폴트 분기(메모 있으면 메모, 없으면 폴백)가 깔끔해진다.
    private static String normalizeMemo(String memo) {
        if (memo == null) return null;
        String trimmed = memo.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static void validateDateInChallenge(Challenge challenge, LocalDateTime dt) {
        if (dt == null || !challenge.containsDate(dt.toLocalDate())) {
            throw new BusinessException(ErrorCode.AMOUNT_DATE_OUT_OF_RANGE);
        }
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
