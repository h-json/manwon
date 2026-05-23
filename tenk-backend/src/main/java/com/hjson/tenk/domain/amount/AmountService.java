package com.hjson.tenk.domain.amount;

import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import com.hjson.tenk.domain.amount.dto.AmountCreateRequest;
import com.hjson.tenk.domain.amount.dto.AmountRecordResult;
import com.hjson.tenk.domain.amount.dto.AmountResponse;
import com.hjson.tenk.domain.amount.dto.AmountUpdateRequest;
import com.hjson.tenk.domain.amount.dto.AmountUpdateRequest.VideoAction;
import com.hjson.tenk.domain.amount.event.AmountRecordedEvent;
import com.hjson.tenk.domain.challenge.Challenge;
import com.hjson.tenk.domain.challenge.ChallengeService;
import com.hjson.tenk.domain.media.LocalFileStorage;
import com.hjson.tenk.domain.media.LocalFileStorage.StoredFile;
import com.hjson.tenk.domain.media.MediaFile;
import com.hjson.tenk.domain.media.MediaFileRepository;
import java.time.LocalDate;
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
    public AmountRecordResult record(Long userId, Long challengeId,
                                     AmountCreateRequest request, MultipartFile video) {
        Challenge challenge = challengeService.loadOwned(userId, challengeId);
        LocalDateTime now = LocalDateTime.now();
        LocalDate today = now.toLocalDate();
        if (challenge.isFinished(today)) {
            throw new BusinessException(ErrorCode.CHALLENGE_ALREADY_FINISHED);
        }
        if (!challenge.isStarted(today)) {
            throw new BusinessException(ErrorCode.CHALLENGE_NOT_STARTED);
        }

        boolean noSpend = Boolean.TRUE.equals(request.noSpend());
        LocalDateTime spentDt;
        int removedNoSpendCount = 0;

        if (noSpend) {
            // 무지출은 일시 입력 불가 — 클라이언트가 보낸 dateTime 은 의도적으로 무시한다.
            // (도메인: "오늘 하루 지출이 없다" 만 의미 있는 행위이므로 과거/미래 무지출 자체가 성립 X)
            spentDt = now;
            // 1차 방어선: 서비스 검증으로 친절한 에러. 2차 방어선: DB uk_amount_no_spend_day 인덱스.
            if (!findNoSpendOn(challenge, today).isEmpty()) {
                throw new BusinessException(ErrorCode.AMOUNT_NO_SPEND_ALREADY_EXISTS);
            }
        } else {
            spentDt = request.dateTime() != null ? request.dateTime() : now;
            // 지출 등록 시 같은 날 이미 무지출이 있으면 → 무지출 row + 첨부 영상 까지 자동 삭제.
            // "그 날이 무지출이냐 아니냐" 가 데이터상 모호해지지 않도록.
            List<Amount> sameDayNoSpend = findNoSpendOn(challenge, spentDt.toLocalDate());
            for (Amount old : sameDayNoSpend) {
                deleteAmountWithMedia(old);
            }
            removedNoSpendCount = sameDayNoSpend.size();
        }

        Amount amount = noSpend
                ? Amount.noSpend(challenge, request.memo(), spentDt)
                : Amount.spend(challenge, request.category(), request.content(),
                        request.amount() == null ? -1 : request.amount(), request.memo(), spentDt);
        amountRepository.save(amount);

        // 영상은 지출/무지출 모두 선택. 첨부된 경우에만 저장.
        List<MediaFile> savedFiles = Collections.emptyList();
        if (video != null && !video.isEmpty()) {
            StoredFile stored = storage.store(video, "amounts/" + challengeId);
            MediaFile media = mediaFileRepository.save(
                    MediaFile.create(amount, stored.relativePath(), stored.originalName()));
            savedFiles = List.of(media);
        }

        eventPublisher.publishEvent(new AmountRecordedEvent(amount.getId(), userId, challengeId));
        return AmountRecordResult.of(amount, savedFiles, removedNoSpendCount);
    }

    public List<AmountResponse> listByChallenge(Long userId, Long challengeId) {
        Challenge challenge = challengeService.loadOwned(userId, challengeId);
        return amountRepository.findByChallengeOrderBySpentDtAscCreatedDtAsc(challenge).stream()
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
        deleteAmountWithMedia(amount);
    }

    /// 기록 수정. 시간(지출의 spentDt 의 LocalTime)/내용/메모/영상 변경.
    /// 지출의 날짜는 변경 불가 (시간만) — 기존 spentDt 의 LocalDate 를 그대로 유지한다.
    /// 무지출은 일시 자체가 서버 now() 강제이므로 request.time() 은 무시.
    @Transactional
    public AmountResponse update(Long userId, Long challengeId, Long amountId,
                                 AmountUpdateRequest request, MultipartFile video) {
        Amount amount = amountRepository.findById(amountId)
                .orElseThrow(() -> new BusinessException(ErrorCode.AMOUNT_NOT_FOUND));
        Challenge challenge = challengeService.loadOwned(userId, challengeId);
        if (!amount.getChallenge().getId().equals(challenge.getId())) {
            throw new BusinessException(ErrorCode.AMOUNT_NOT_FOUND);
        }
        LocalDate today = LocalDate.now();
        if (challenge.isFinished(today)) {
            throw new BusinessException(ErrorCode.CHALLENGE_ALREADY_FINISHED);
        }
        if (!challenge.isStarted(today)) {
            throw new BusinessException(ErrorCode.CHALLENGE_NOT_STARTED);
        }

        // 지출: 기존 날짜 유지 + 새 시간 결합. 시간 미지정이면 기존 시각 유지.
        // 무지출: spentDt 자체를 안 건드린다 (Amount.update 가 인자 무시).
        LocalDateTime newSpentDt = amount.getSpentDt();
        if (!amount.isNoSpend() && request.time() != null) {
            newSpentDt = LocalDateTime.of(amount.getSpentDt().toLocalDate(), request.time());
        }
        // 무지출은 amount/category/content 를 항상 0/null 로 강제 — 클라이언트가 무엇을 보내든 무시.
        // (Amount.update 의 noSpend 분기가 category/content 는 자체적으로 null 화 하지만
        //  amount 인자는 0 만 허용하므로 여기서도 미리 0 으로 정규화한다.)
        int normalizedAmount = amount.isNoSpend()
                ? 0
                : (request.amount() == null ? -1 : request.amount());
        amount.update(
                request.category(),
                request.content(),
                normalizedAmount,
                request.memo(),
                newSpentDt);

        applyVideoAction(amount, challengeId, request.videoAction(), video);
        return AmountResponse.of(amount, mediaFileRepository.findByAmount(amount));
    }

    private void applyVideoAction(Amount amount, Long challengeId,
                                  VideoAction action, MultipartFile video) {
        switch (action) {
            case KEEP -> {
                // no-op
            }
            case REMOVE -> deleteMediaOf(amount);
            case REPLACE -> {
                if (video == null || video.isEmpty()) {
                    throw new BusinessException(ErrorCode.INVALID_INPUT);
                }
                deleteMediaOf(amount);
                StoredFile stored = storage.store(video, "amounts/" + challengeId);
                mediaFileRepository.save(
                        MediaFile.create(amount, stored.relativePath(), stored.originalName()));
            }
        }
    }

    private void deleteMediaOf(Amount amount) {
        List<MediaFile> existing = mediaFileRepository.findByAmount(amount);
        for (MediaFile mediaFile : existing) {
            storage.deleteQuietly(mediaFile.getFilePath());
        }
        mediaFileRepository.deleteByAmount(amount);
    }

    private List<Amount> findNoSpendOn(Challenge challenge, LocalDate day) {
        LocalDateTime from = day.atStartOfDay();
        LocalDateTime toExclusive = day.plusDays(1).atStartOfDay();
        return amountRepository.findNoSpendInChallengeOnDay(challenge, from, toExclusive);
    }

    private void deleteAmountWithMedia(Amount amount) {
        List<MediaFile> mediaFiles = mediaFileRepository.findByAmount(amount);
        for (MediaFile mediaFile : mediaFiles) {
            storage.deleteQuietly(mediaFile.getFilePath());
        }
        mediaFileRepository.deleteByAmount(amount);
        amountRepository.delete(amount);
    }
}
