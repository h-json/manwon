package com.hjson.tenk.domain.amount;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

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
import com.hjson.tenk.domain.user.AuthProvider;
import com.hjson.tenk.domain.user.User;
import java.time.LocalDate;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.multipart.MultipartFile;

@ExtendWith(MockitoExtension.class)
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
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null);

        assertThatThrownBy(() -> service.record(100L, 1L, req, videoPart()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_ALREADY_FINISHED);
        verify(amountRepository, never()).save(any());
    }

    @Test
    void record_on_not_started_challenge_throws() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(notStartedChallenge());
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null);

        assertThatThrownBy(() -> service.record(100L, 1L, req, videoPart()))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.CHALLENGE_NOT_STARTED);
        verify(amountRepository, never()).save(any());
    }

    @Test
    void record_spend_without_video_throws_video_required() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(ongoingChallenge());
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null);

        assertThatThrownBy(() -> service.record(100L, 1L, req, null))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_VIDEO_REQUIRED);
    }

    @Test
    void record_spend_with_empty_video_throws_video_required() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(ongoingChallenge());
        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 1_000, false, null);
        MockMultipartFile empty = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[0]);

        assertThatThrownBy(() -> service.record(100L, 1L, req, empty))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode").isEqualTo(ErrorCode.AMOUNT_VIDEO_REQUIRED);
    }

    @Test
    void record_no_spend_without_video_succeeds_and_publishes_event() {
        given(challengeService.loadOwned(100L, 1L)).willReturn(ongoingChallenge());
        AmountCreateRequest req = new AmountCreateRequest(null, null, null, true, null);

        AmountResponse response = service.record(100L, 1L, req, null);

        assertThat(response.noSpend()).isTrue();
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

        AmountCreateRequest req = new AmountCreateRequest("food", "lunch", 5_000, false, null);

        AmountResponse response = service.record(100L, 1L, req, videoPart());

        assertThat(response.noSpend()).isFalse();
        assertThat(response.amount()).isEqualTo(5_000);
        verify(amountRepository).save(any(Amount.class));
        verify(storage).store(any(MultipartFile.class), any(String.class));
        verify(mediaFileRepository).save(any(MediaFile.class));
        verify(eventPublisher).publishEvent(any(AmountRecordedEvent.class));
    }
}
