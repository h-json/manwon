package com.hjson.tenk.domain.amount;

import com.hjson.tenk.domain.challenge.Challenge;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AmountRepository extends JpaRepository<Amount, Long> {

    List<Amount> findByChallengeOrderByCreatedDtAsc(Challenge challenge);

    @Query("""
            select coalesce(sum(a.amount), 0)
            from Amount a
            where a.challenge = :challenge
            """)
    long sumByChallenge(@Param("challenge") Challenge challenge);

    @Query("""
            select a from Amount a
            where a.challenge.user.id = :userId
              and a.createdDt >= :from
              and a.createdDt < :to
            order by a.createdDt asc
            """)
    List<Amount> findUserAmountsBetween(@Param("userId") Long userId,
                                        @Param("from") LocalDateTime from,
                                        @Param("to") LocalDateTime to);
}
