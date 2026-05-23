package com.hjson.tenk.domain.media;

import com.hjson.tenk.domain.amount.Amount;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaFileRepository extends JpaRepository<MediaFile, Long> {

    List<MediaFile> findByAmount(Amount amount);

    void deleteByAmount(Amount amount);

    /// 다운로드 컨트롤러 전용 — 소유자 검증을 위해 amount → challenge → user 까지 한 번에 끌어온다.
    /// 트랜잭션 밖에서 `mediaFile.getAmount().getChallenge().getUser().getId()` 체이닝이 풀리는 LAZY 함정
    /// 회피용 ([MediaController](../MediaController.java) 다운로드 경로 회귀 가드).
    @Query("""
        select mf from MediaFile mf
        join fetch mf.amount a
        join fetch a.challenge c
        join fetch c.user
        where mf.id = :id
    """)
    Optional<MediaFile> findByIdWithAmountChallengeUser(@Param("id") Long id);
}
