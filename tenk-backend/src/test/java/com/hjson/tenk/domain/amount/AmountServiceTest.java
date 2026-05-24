package com.hjson.tenk.domain.amount;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

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
import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.multipart.MultipartFile;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class AmountServiceTest {

    @Mock AmountRepository amountRepository;
    @Mock MediaFileRepository mediaFileRepository;
    @Mock ChallengeService challengeService;
    @Mock LocalFileStorage storage;
    @Mock ApplicationEventPublisher eventPublisher;

    @InjectMocks AmountService service;

    private User user;

    @BeforeEach
    void setUp() {
        user = User.create(AuthProvider.KAKAO, "kakao-1", "u@example.com", "tester");
        ReflectionTestUtils.setField(user, "id", 100L);
    }

    private Challenge ongoingChallenge() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today, today.plusDays(3), 10_000);
        ReflectionTestUtils.setField(c, "id", 1L);
        return c;
    }

    private Challenge finishedChallenge() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today, today, 10_000);
        ReflectionTestUtils.setField(c, "id", 1L);
        ReflectionTestUtils.setField(c, "startDate", today.minusDays(2));
        ReflectionTestUtils.setField(c, "endDate", today.minusDays(1));
        return c;
    }

    private Challenge notStartedChallenge() {
        LocalDate today = LocalDate.now();
        Challenge c = Challenge.create(user, today.plusDays(2), today.plusDays(5), 10_000);
        ReflectionTestUtils.setField(c, "id", 1L);
        return c;
    }

    private MultipartFile videoPart() {
        return new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[]{1, 2, 3});
    }

    @Test
    void record_on_finished_challenge_throws_already_finished() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(finishedChallenge());
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null, null);

        assertThatThrownBy(() -> service.record(100L, 1L, req, videoPart()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_ALREADY_FINISHED);
        verify(amountRepository, never()).save(any());
    }

    @Test
    void record_on_not_started_challenge_throws() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(notStartedChallenge());
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null, null);

        assertThatThrownBy(() -> service.record(100L, 1L, req, videoPart()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_NOT_STARTED);
        verify(amountRepository, never()).save(any());
    }

    @Test
    void record_spend_without_video_succeeds_and_skips_storage() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(ongoingChallenge());
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null, null);

        AmountRecordResult result = service.record(100L, 1L, req, null);

        assertThat(result.amount().noSpend()).isFalse();
        assertThat(result.amount().mediaFiles()).isEmpty();
        verify(amountRepository).save(any(Amount.class));
        verify(storage, never()).store(any(), any());
        verify(mediaFileRepository, never()).save(any());
        verify(eventPublisher).publishEvent(any(AmountRecordedEvent.class));
    }

    @Test
    void record_spend_with_empty_video_succeeds_and_skips_storage() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(ongoingChallenge());
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null, null);
        MockMultipartFile empty = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[0]);

        AmountRecordResult result = service.record(100L, 1L, req, empty);

        assertThat(result.amount().mediaFiles()).isEmpty();
        verify(storage, never()).store(any(), any());
        verify(mediaFileRepository, never()).save(any());
    }

    @Test
    void record_no_spend_without_video_succeeds_and_publishes_event() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(ongoingChallenge());
        AmountCreateRequest req = new AmountCreateRequest(null, null, null, true, null, null);

        AmountRecordResult result = service.record(100L, 1L, req, null);

        assertThat(result.amount().noSpend()).isTrue();
        assertThat(result.removedNoSpendCount()).isZero();
        verify(amountRepository).save(any(Amount.class));
        verify(eventPublisher).publishEvent(any(AmountRecordedEvent.class));
        verify(storage, never()).store(any(), any());
        verify(mediaFileRepository, never()).save(any());
    }

    @Test
    void record_spend_happy_path_stores_video_and_publishes_event() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(ongoingChallenge());
        given(storage.store(any(MultipartFile.class), any(String.class)))
                .willReturn(new StoredFile("amounts/1/2026/05/19/uuid.mp4", "clip.mp4"));
        given(mediaFileRepository.save(any(MediaFile.class)))
                .willAnswer(invocation -> invocation.getArgument(0));

        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 5_000, false, null, null);

        AmountRecordResult result = service.record(100L, 1L, req, videoPart());

        assertThat(result.amount().noSpend()).isFalse();
        assertThat(result.amount().amount()).isEqualTo(5_000);
        assertThat(result.removedNoSpendCount()).isZero();
        verify(amountRepository).save(any(Amount.class));
        verify(storage).store(any(MultipartFile.class), any(String.class));
        verify(mediaFileRepository).save(any(MediaFile.class));
        verify(eventPublisher).publishEvent(any(AmountRecordedEvent.class));
    }

    @Test
    void record_no_spend_ignores_client_datetime_and_uses_server_now() {
        Challenge challenge = ongoingChallenge();
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        // 클라이언트가 챌린지 안의 다른 날짜를 보내도 무시 — 서버가 now() 를 박는다.
        LocalDateTime clientSent = LocalDate.now().plusDays(1).atTime(10, 0);
        AmountCreateRequest req = new AmountCreateRequest(null, null, null, true, null, clientSent);

        ArgumentCaptor<Amount> captor = ArgumentCaptor.forClass(Amount.class);
        given(amountRepository.save(captor.capture())).willAnswer(inv -> inv.getArgument(0));

        service.record(100L, 1L, req, null);

        Amount saved = captor.getValue();
        assertThat(saved.isNoSpend()).isTrue();
        assertThat(saved.getSpentDt().toLocalDate()).isEqualTo(LocalDate.now());
    }

    @Test
    void record_no_spend_throws_when_already_exists_today() {
        Challenge challenge = ongoingChallenge();
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        Amount existing = Amount.noSpend(challenge, null, LocalDate.now().atTime(8, 0));
        given(amountRepository.findNoSpendInChallengeOnDay(eq(challenge), any(), any()))
                .willReturn(List.of(existing));

        AmountCreateRequest req = new AmountCreateRequest(null, null, null, true, null, null);

        assertThatThrownBy(() -> service.record(100L, 1L, req, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_NO_SPEND_ALREADY_EXISTS);
        verify(amountRepository, never()).save(any());
        verify(eventPublisher, never()).publishEvent(any());
    }

    @Test
    void update_spend_changes_time_but_keeps_date() {
        Challenge challenge = ongoingChallenge();
        LocalDateTime original = LocalDate.now().atTime(9, 0);
        Amount existing = Amount.spend(challenge, "food", "lunch", 5_000, null, original);
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        given(mediaFileRepository.findByAmount(existing)).willReturn(List.of());

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, "수정 메모", LocalTime.of(22, 30), VideoAction.KEEP);
        AmountResponse res = service.update(100L, 1L, 42L, req, null);

        assertThat(res.spentDt().toLocalDate()).isEqualTo(LocalDate.now());
        assertThat(res.spentDt().getHour()).isEqualTo(22);
        assertThat(res.spentDt().getMinute()).isEqualTo(30);
        assertThat(res.memo()).isEqualTo("수정 메모");
        verify(storage, never()).store(any(), any());
        verify(storage, never()).deleteQuietly(any());
    }

    @Test
    void update_video_keep_leaves_media_intact() {
        Challenge challenge = ongoingChallenge();
        Amount existing = Amount.spend(challenge, "food", "lunch", 5_000, null,
                LocalDate.now().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, null, VideoAction.KEEP);
        service.update(100L, 1L, 42L, req, null);

        verify(storage, never()).store(any(), any());
        verify(storage, never()).deleteQuietly(any());
        verify(mediaFileRepository, never()).deleteByAmount(any());
        verify(mediaFileRepository, never()).save(any(MediaFile.class));
    }

    @Test
    void update_video_remove_deletes_media_and_files() {
        Challenge challenge = ongoingChallenge();
        Amount existing = Amount.spend(challenge, "food", "lunch", 5_000, null,
                LocalDate.now().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        MediaFile attached = mock(MediaFile.class);
        given(attached.getFilePath()).willReturn("amounts/1/old.mp4");
        given(mediaFileRepository.findByAmount(existing)).willReturn(List.of(attached));

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, null, VideoAction.REMOVE);
        service.update(100L, 1L, 42L, req, null);

        verify(storage).deleteQuietly("amounts/1/old.mp4");
        verify(mediaFileRepository).deleteByAmount(existing);
        verify(storage, never()).store(any(), any());
    }

    @Test
    void update_video_replace_swaps_media_file() {
        Challenge challenge = ongoingChallenge();
        Amount existing = Amount.spend(challenge, "food", "lunch", 5_000, null,
                LocalDate.now().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        MediaFile attached = mock(MediaFile.class);
        given(attached.getFilePath()).willReturn("amounts/1/old.mp4");
        given(mediaFileRepository.findByAmount(existing)).willReturn(List.of(attached));
        given(storage.store(any(MultipartFile.class), any(String.class)))
                .willReturn(new StoredFile("amounts/1/new.mp4", "clip.mp4"));
        given(mediaFileRepository.save(any(MediaFile.class)))
                .willAnswer(inv -> inv.getArgument(0));

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, null, VideoAction.REPLACE);
        service.update(100L, 1L, 42L, req, videoPart());

        verify(storage).deleteQuietly("amounts/1/old.mp4");
        verify(mediaFileRepository).deleteByAmount(existing);
        verify(storage).store(any(MultipartFile.class), any(String.class));
        verify(mediaFileRepository).save(any(MediaFile.class));
    }

    @Test
    void update_video_replace_without_video_part_throws_invalid_input() {
        Challenge challenge = ongoingChallenge();
        Amount existing = Amount.spend(challenge, "food", "lunch", 5_000, null,
                LocalDate.now().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, null, VideoAction.REPLACE);

        assertThatThrownBy(() -> service.update(100L, 1L, 42L, req, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.INVALID_INPUT);
    }

    @Test
    void update_no_spend_ignores_time_and_content_changes() {
        Challenge challenge = ongoingChallenge();
        LocalDateTime serverNow = LocalDate.now().atTime(8, 0);
        Amount existing = Amount.noSpend(challenge, null, serverNow);
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        given(mediaFileRepository.findByAmount(existing)).willReturn(List.of());

        // 클라이언트가 time + category/content/amount 다 채워 보내도 무시.
        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "snack", 500, "수정 메모", LocalTime.of(23, 59), VideoAction.KEEP);
        AmountResponse res = service.update(100L, 1L, 42L, req, null);

        assertThat(res.noSpend()).isTrue();
        assertThat(res.category()).isNull();
        assertThat(res.content()).isNull();
        assertThat(res.amount()).isZero();
        assertThat(res.memo()).isEqualTo("수정 메모");
        assertThat(res.spentDt()).isEqualTo(serverNow);
    }

    @Test
    void update_on_finished_challenge_throws_already_finished() {
        Challenge finished = finishedChallenge();
        Amount existing = Amount.spend(finished, "food", "lunch", 5_000, null,
                finished.getStartDate().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(finished);

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, LocalTime.of(10, 0), VideoAction.KEEP);

        assertThatThrownBy(() -> service.update(100L, 1L, 42L, req, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_ALREADY_FINISHED);
    }

    @Test
    void update_on_not_started_challenge_throws_not_started() {
        Challenge notStarted = notStartedChallenge();
        Amount existing = Amount.spend(ongoingChallenge(), "food", "lunch", 5_000, null,
                LocalDate.now().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        ReflectionTestUtils.setField(existing, "challenge", notStarted);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(notStarted);

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, LocalTime.of(10, 0), VideoAction.KEEP);

        assertThatThrownBy(() -> service.update(100L, 1L, 42L, req, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_NOT_STARTED);
    }

    @Test
    void update_amount_not_found_throws() {
        given(amountRepository.findById(42L)).willReturn(Optional.empty());

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, null, VideoAction.KEEP);

        assertThatThrownBy(() -> service.update(100L, 1L, 42L, req, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_NOT_FOUND);
        verify(challengeService, never()).loadOwned(any(), any());
    }

    @Test
    void update_amount_belongs_to_different_challenge_throws_not_found() {
        Challenge requested = ongoingChallenge();
        Challenge other = ongoingChallenge();
        ReflectionTestUtils.setField(other, "id", 999L);
        Amount existing = Amount.spend(other, "food", "lunch", 5_000, null,
                LocalDate.now().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(requested);

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, null, VideoAction.KEEP);

        assertThatThrownBy(() -> service.update(100L, 1L, 42L, req, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_NOT_FOUND);
        verify(storage, never()).store(any(), any());
        verify(storage, never()).deleteQuietly(any());
    }

    @Test
    void update_spend_with_null_time_keeps_existing_spent_dt() {
        Challenge challenge = ongoingChallenge();
        LocalDateTime original = LocalDate.now().atTime(9, 15, 30);
        Amount existing = Amount.spend(challenge, "food", "lunch", 5_000, null, original);
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        given(mediaFileRepository.findByAmount(existing)).willReturn(List.of());

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, "메모만 변경", null, VideoAction.KEEP);
        AmountResponse res = service.update(100L, 1L, 42L, req, null);

        assertThat(res.spentDt()).isEqualTo(original);
        assertThat(res.memo()).isEqualTo("메모만 변경");
    }

    @Test
    void update_video_replace_with_empty_video_throws_invalid_input() {
        Challenge challenge = ongoingChallenge();
        Amount existing = Amount.spend(challenge, "food", "lunch", 5_000, null,
                LocalDate.now().atTime(9, 0));
        ReflectionTestUtils.setField(existing, "id", 42L);
        given(amountRepository.findById(42L)).willReturn(Optional.of(existing));
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);

        AmountUpdateRequest req = new AmountUpdateRequest(
                "food", "lunch", 5_000, null, null, VideoAction.REPLACE);
        MockMultipartFile empty = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[0]);

        assertThatThrownBy(() -> service.update(100L, 1L, 42L, req, empty))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.INVALID_INPUT);
        verify(storage, never()).store(any(), any());
    }

    @Test
    void record_spend_deletes_same_day_no_spend_and_reports_count() {
        Challenge challenge = ongoingChallenge();
        given(challengeService.loadOwned(100L, 1L)).willReturn(challenge);
        Amount existingNoSpend = Amount.noSpend(challenge, null, LocalDate.now().atTime(8, 0));
        ReflectionTestUtils.setField(existingNoSpend, "id", 555L);
        given(amountRepository.findNoSpendInChallengeOnDay(eq(challenge), any(), any()))
                .willReturn(List.of(existingNoSpend));
        MediaFile attached = mock(MediaFile.class);
        given(attached.getFilePath()).willReturn("amounts/1/old.mp4");
        given(mediaFileRepository.findByAmount(existingNoSpend)).willReturn(List.of(attached));
        given(storage.store(any(MultipartFile.class), any(String.class)))
                .willReturn(new StoredFile("amounts/1/new.mp4", "clip.mp4"));
        given(mediaFileRepository.save(any(MediaFile.class)))
                .willAnswer(inv -> inv.getArgument(0));

        AmountCreateRequest req = new AmountCreateRequest("food", "snack", 3000, false, null, null);
        AmountRecordResult result = service.record(100L, 1L, req, videoPart());

        assertThat(result.removedNoSpendCount()).isEqualTo(1);
        verify(storage).deleteQuietly("amounts/1/old.mp4");
        verify(mediaFileRepository).deleteByAmount(existingNoSpend);
        verify(amountRepository).delete(existingNoSpend);
    }
}
