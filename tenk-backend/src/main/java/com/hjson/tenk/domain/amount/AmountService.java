package com.hjson.tenk.domain.amount;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.amount.dto.AmountCreateRequest;
import com.hjson.tenk.domain.amount.dto.AmountResponse;
import com.hjson.tenk.domain.amount.event.AmountRecordedEvent;
import com.hjson.tenk.domain.challenge.Challenge;
import com.hjson.tenk.domain.challenge.ChallengeService;
import com.hjson.tenk.domain.media.LocalFileStorage;
import com.hjson.tenk.domain.media.LocalFileStorage.StoredFile;
import com.hjson.tenk.domain.media.MediaFile;
import com.hjson.tenk.domain.media.MediaFileRepository;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AmountService {

    private final AmountRepository amountRepository;
    private final MediaFileRepository mediaFileRepository;
    private final ChallengeService challengeService;
    private final LocalFileStorage storage;
    private final ApplicationEventPublisher eventPublisher;

    @Transactional
    public AmountResponse record(Long userId, Long challengeId,
                                 AmountCreateRequest request, MultipartFile video) {
        Challenge challenge = challengeService.loadOwned(userId, challengeId);
        if (challenge.isFinished(LocalDateTime.now())) {
            throw new BusinessException(ErrorCode.CHALLENGE_ALREADY_FINISHED);
        }

        boolean noSpend = Boolean.TRUE.equals(request.noSpend());
        Amount amount = noSpend
                ? Amount.noSpend(challenge)
                : Amount.spend(challenge, request.category(), request.content(),
                        request.amount() == null ? -1 : request.amount());
        amountRepository.save(amount);

        List<MediaFile> savedFiles = Collections.emptyList();
        if (!noSpend) {
            if (video == null || video.isEmpty()) {
                throw new BusinessException(ErrorCode.AMOUNT_VIDEO_REQUIRED);
            }
            StoredFile stored = storage.store(video, "amounts/" + challengeId);
            MediaFile media = mediaFileRepository.save(
                    MediaFile.create(amount, stored.relativePath(), stored.originalName()));
            savedFiles = List.of(media);
        } else if (video != null && !video.isEmpty()) {
            StoredFile stored = storage.store(video, "amounts/" + challengeId);
            MediaFile media = mediaFileRepository.save(
                    MediaFile.create(amount, stored.relativePath(), stored.originalName()));
            savedFiles = List.of(media);
        }

        eventPublisher.publishEvent(new AmountRecordedEvent(amount.getId(), userId, challengeId));
        return AmountResponse.of(amount, savedFiles);
    }

    public List<AmountResponse> listByChallenge(Long userId, Long challengeId) {
        Challenge challenge = challengeService.loadOwned(userId, challengeId);
        return amountRepository.findByChallengeOrderByCreatedDtAsc(challenge).stream()
                .map(a -> AmountResponse.of(a, mediaFileRepository.findByAmount(a)))
                .toList();
    }

    @Transactional
    public void delete(Long userId, Long challengeId, Long amountId) {
        Amount amount = amountRepository.findById(amountId)
                .orElseThrow(() -> new BusinessException(ErrorCode.AMOUNT_NOT_FOUND));
        Challenge challenge = challengeService.loadOwned(userId, challengeId);
        if (!amount.getChallenge().getId().equals(challenge.getId())) {
            throw new BusinessException(ErrorCode.AMOUNT_NOT_FOUND);
        }
        List<MediaFile> mediaFiles = mediaFileRepository.findByAmount(amount);
        for (MediaFile mediaFile : mediaFiles) {
            storage.deleteQuietly(mediaFile.getFilePath());
        }
        mediaFileRepository.deleteByAmount(amount);
        amountRepository.delete(amount);
    }
}
