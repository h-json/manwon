package com.hjson.tenk.domain.challenge;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.amount.AmountRepository;
import com.hjson.tenk.domain.challenge.dto.ChallengeCreateRequest;
import com.hjson.tenk.domain.challenge.dto.ChallengeResponse;
import com.hjson.tenk.domain.challenge.event.ChallengeFinishedEvent;
import com.hjson.tenk.domain.user.User;
import com.hjson.tenk.domain.user.UserService;
import java.time.LocalDateTime;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ChallengeService {

    private final ChallengeRepository challengeRepository;
    private final AmountRepository amountRepository;
    private final UserService userService;
    private final ApplicationEventPublisher eventPublisher;

    @Transactional
    public ChallengeResponse create(Long userId, ChallengeCreateRequest request) {
        User user = userService.getActiveUser(userId);
        Challenge challenge = Challenge.create(user, request.startDt(), request.endDt(), request.targetAmount());
        return ChallengeResponse.of(challengeRepository.save(challenge), 0L, LocalDateTime.now());
    }

    public ChallengeResponse getOne(Long userId, Long challengeId) {
        Challenge challenge = loadOwned(userId, challengeId);
        long total = amountRepository.sumByChallenge(challenge);
        return ChallengeResponse.of(challenge, total, LocalDateTime.now());
    }

    public List<ChallengeResponse> listMine(Long userId, boolean onlyActive) {
        User user = userService.getActiveUser(userId);
        LocalDateTime now = LocalDateTime.now();
        List<Challenge> challenges = onlyActive
                ? challengeRepository.findByUserAndDeletedFalseAndEndDtAfterOrderByStartDtAsc(user, now)
                : challengeRepository.findByUserAndDeletedFalseOrderByStartDtDesc(user);
        return challenges.stream()
                .map(c -> ChallengeResponse.of(c, amountRepository.sumByChallenge(c), now))
                .toList();
    }

    @Transactional
    public void delete(Long userId, Long challengeId) {
        Challenge challenge = loadOwned(userId, challengeId);
        challenge.softDelete();
    }

    @Transactional
    public ChallengeResponse finalizeIfDue(Long userId, Long challengeId) {
        Challenge challenge = loadOwned(userId, challengeId);
        finalizeInternal(challenge);
        long total = amountRepository.sumByChallenge(challenge);
        return ChallengeResponse.of(challenge, total, LocalDateTime.now());
    }

    @Transactional
    public int finalizeAllDue() {
        List<Challenge> dueChallenges = challengeRepository
                .findByDeletedFalseAndResultIsNullAndEndDtBefore(LocalDateTime.now());
        for (Challenge challenge : dueChallenges) {
            finalizeInternal(challenge);
        }
        return dueChallenges.size();
    }

    public Challenge loadOwned(Long userId, Long challengeId) {
        Challenge challenge = challengeRepository.findByIdAndDeletedFalse(challengeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.CHALLENGE_NOT_FOUND));
        if (!challenge.getUser().getId().equals(userId)) {
            throw new BusinessException(ErrorCode.CHALLENGE_NOT_OWNER);
        }
        return challenge;
    }

    private void finalizeInternal(Challenge challenge) {
        if (challenge.getResult() != null) {
            return;
        }
        if (!challenge.isFinished(LocalDateTime.now())) {
            return;
        }
        long total = amountRepository.sumByChallenge(challenge);
        ChallengeResult result = total <= challenge.getTargetAmount()
                ? ChallengeResult.SUCCESS
                : ChallengeResult.FAIL;
        challenge.markResult(result);
        eventPublisher.publishEvent(new ChallengeFinishedEvent(
                challenge.getId(), challenge.getUser().getId(), result));
    }
}
