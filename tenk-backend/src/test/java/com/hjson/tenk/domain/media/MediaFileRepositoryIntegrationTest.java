package com.hjson.tenk.domain.media;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.hjson.tenk.domain.amount.Amount;
import com.hjson.tenk.domain.amount.AmountRepository;
import com.hjson.tenk.domain.challenge.Challenge;
import com.hjson.tenk.domain.challenge.ChallengeRepository;
import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;
import com.hjson.tenk.domain.user.UserRepository;
import com.hjson.tenk.support.IntegrationTestBase;
import java.time.LocalDate;
import org.hibernate.LazyInitializationException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

/**
 * {@link MediaFileRepository#findByIdWithAmountChallengeUser} 회귀 가드.
 *
 * <p>{@link MediaController} 의 download/meta 가 트랜잭션 밖에서
 * {@code mediaFile.getAmount().getChallenge().getUser().getId()} 체이닝을 풀기 때문에
 * LAZY 연관이 같이 끌어와지지 않으면 {@link LazyInitializationException} 으로 터진다. 영상
 * export 기능이 의존하는 다운로드 경로의 핵심 contract.
 *
 * <p>OSIV 가 꺼져 있음 ({@code application.yaml} 의 {@code open-in-view: false}) 을 전제로 한다 —
 * 즉, 트랜잭션 밖 LAZY 접근은 정말로 터진다.
 */
class MediaFileRepositoryIntegrationTest extends IntegrationTestBase {

    @Autowired UserRepository userRepository;
    @Autowired ChallengeRepository challengeRepository;
    @Autowired AmountRepository amountRepository;
    @Autowired MediaFileRepository mediaFileRepository;

    @Test
    @DisplayName("JOIN FETCH 쿼리는 트랜잭션 밖에서 amount → challenge → user 체이닝이 풀린다")
    void fetchJoinChainResolvesOutsideTransaction() {
        Long mediaFileId = seedMediaFile("kakao-fetch");

        MediaFile mediaFile = mediaFileRepository
                .findByIdWithAmountChallengeUser(mediaFileId)
                .orElseThrow();

        // MediaController 가 실제로 하는 체이닝 — 트랜잭션 밖에서 다 풀려야 한다.
        Long ownerId = mediaFile.getAmount().getChallenge().getUser().getId();
        assertThat(ownerId).isNotNull();
        assertThat(mediaFile.getAmount().getId()).isNotNull();
        assertThat(mediaFile.getOriginalName()).isEqualTo("test.mp4");
    }

    @Test
    @DisplayName("기본 findById 는 트랜잭션 밖에서 LAZY 가 안 풀려 터진다 — JOIN FETCH 가 필요한 이유")
    void plainFindByIdThrowsLazyOutsideTransaction() {
        Long mediaFileId = seedMediaFile("kakao-lazy");

        MediaFile mediaFile = mediaFileRepository.findById(mediaFileId).orElseThrow();

        assertThatThrownBy(() -> mediaFile.getAmount().getChallenge().getUser().getId())
                .isInstanceOf(LazyInitializationException.class);
    }

    /// `tx.execute(...)` 안에서 user/challenge/amount/media_file 을 박고 mediaFileId 만 꺼내온다.
    /// 모두 LAZY 매핑이라 같은 트랜잭션 안에서 저장한 직후라도 트랜잭션이 닫히면 chain 이 끊긴다.
    private Long seedMediaFile(String providerUserId) {
        return tx.execute(status -> {
            User user = userRepository.save(
                    User.create(AuthProvider.KAKAO, providerUserId, providerUserId + "@example.com", "tester"));
            Challenge challenge = challengeRepository.save(
                    Challenge.create(user, LocalDate.now(), LocalDate.now().plusDays(1), 10_000));
            Amount amount = amountRepository.save(
                    Amount.spend(challenge, "x", "x", 100, null, LocalDate.now().atTime(12, 0)));
            MediaFile mediaFile = mediaFileRepository.save(
                    MediaFile.create(amount, "amounts/1/test.mp4", "test.mp4"));
            return mediaFile.getId();
        });
    }
}
