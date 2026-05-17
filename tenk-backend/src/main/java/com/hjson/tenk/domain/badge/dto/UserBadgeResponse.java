package com.hjson.tenk.domain.badge.dto;

import com.hjson.tenk.domain.badge.BadgeType;
import com.hjson.tenk.domain.badge.UserBadge;
import java.time.LocalDateTime;

public record UserBadgeResponse(
        Long userBadgeId,
        Long badgeId,
        BadgeType type,
        int conditionValue,
        String iconPath,
        LocalDateTime acquiredDt
) {
    public static UserBadgeResponse from(UserBadge ub) {
        return new UserBadgeResponse(
                ub.getId(),
                ub.getBadge().getId(),
                ub.getBadge().getType(),
                ub.getBadge().getConditionValue(),
                ub.getBadge().getIconPath(),
                ub.getCreatedDt());
    }
}
