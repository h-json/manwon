package com.hjson.tenk.domain.badge;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BadgeRepository extends JpaRepository<Badge, Long> {

    Optional<Badge> findByTypeAndConditionValue(BadgeType type, int conditionValue);

    List<Badge> findByTypeOrderByConditionValueAsc(BadgeType type);
}
