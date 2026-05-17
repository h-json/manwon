package com.hjson.tenk.domain.badge;

import com.hjson.tenk.domain.user.User;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserBadgeRepository extends JpaRepository<UserBadge, Long> {

    boolean existsByUserAndBadge(User user, Badge badge);

    List<UserBadge> findByUserOrderByCreatedDtDesc(User user);
}
