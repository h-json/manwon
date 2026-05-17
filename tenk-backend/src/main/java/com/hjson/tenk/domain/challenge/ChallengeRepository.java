package com.hjson.tenk.domain.challenge;

import com.hjson.tenk.domain.user.User;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ChallengeRepository extends JpaRepository<Challenge, Long> {

    Optional<Challenge> findByIdAndDeletedFalse(Long id);

    List<Challenge> findByUserAndDeletedFalseOrderByStartDtDesc(User user);

    List<Challenge> findByUserAndDeletedFalseAndEndDtAfterOrderByStartDtAsc(User user, LocalDateTime now);

    List<Challenge> findByDeletedFalseAndResultIsNullAndEndDtBefore(LocalDateTime now);
}
