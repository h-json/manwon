package com.hjson.tenk.domain.challenge;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EntityListeners;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.LocalDateTime;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import com.hjson.tenk.domain.user.User;

@Getter
@Entity
@Table(name = "challenge")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@EntityListeners(AuditingEntityListener.class)
public class Challenge {

    public static final int MAX_DURATION_DAYS = 7;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "challenge_id")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "start_dt", nullable = false)
    private LocalDateTime startDt;

    @Column(name = "end_dt", nullable = false)
    private LocalDateTime endDt;

    @Column(name = "target_amount", nullable = false)
    private int targetAmount;

    @Enumerated(EnumType.STRING)
    @Column(name = "result", length = 20)
    private ChallengeResult result;

    @CreatedDate
    @Column(name = "created_dt", nullable = false, updatable = false)
    private LocalDateTime createdDt;

    @LastModifiedDate
    @Column(name = "updated_dt", nullable = false)
    private LocalDateTime updatedDt;

    @Column(name = "is_deleted", nullable = false)
    private boolean deleted;

    @Column(name = "deleted_dt")
    private LocalDateTime deletedDt;

    private Challenge(User user, LocalDateTime startDt, LocalDateTime endDt, int targetAmount) {
        validatePeriod(startDt, endDt);
        this.user = user;
        this.startDt = startDt;
        this.endDt = endDt;
        this.targetAmount = targetAmount;
        this.deleted = false;
    }

    public static Challenge create(User user, LocalDateTime startDt, LocalDateTime endDt, int targetAmount) {
        return new Challenge(user, startDt, endDt, targetAmount);
    }

    public boolean isFinished(LocalDateTime now) {
        return !now.isBefore(endDt);
    }

    public void markResult(ChallengeResult result) {
        if (this.result != null) {
            throw new BusinessException(ErrorCode.CHALLENGE_ALREADY_FINISHED);
        }
        this.result = result;
    }

    public void softDelete() {
        this.deleted = true;
        this.deletedDt = LocalDateTime.now();
    }

    private static void validatePeriod(LocalDateTime startDt, LocalDateTime endDt) {
        if (startDt == null || endDt == null || !endDt.isAfter(startDt)) {
            throw new BusinessException(ErrorCode.CHALLENGE_PERIOD_INVALID);
        }
        long days = Duration.between(startDt, endDt).toDays();
        if (days > MAX_DURATION_DAYS) {
            throw new BusinessException(ErrorCode.CHALLENGE_PERIOD_INVALID);
        }
    }
}
