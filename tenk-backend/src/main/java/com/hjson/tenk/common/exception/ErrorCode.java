package com.hjson.tenk.common.exception;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum ErrorCode {

    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "C0001", "서버 내부 오류가 발생했습니다."),
    INVALID_INPUT(HttpStatus.BAD_REQUEST, "C0002", "잘못된 요청입니다."),
    UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "C0003", "인증이 필요합니다."),
    FORBIDDEN(HttpStatus.FORBIDDEN, "C0004", "접근 권한이 없습니다."),

    USER_NOT_FOUND(HttpStatus.NOT_FOUND, "U0001", "사용자를 찾을 수 없습니다."),
    USER_ALREADY_WITHDRAWN(HttpStatus.BAD_REQUEST, "U0002", "이미 탈퇴한 사용자입니다."),

    AUTH_TOKEN_INVALID(HttpStatus.UNAUTHORIZED, "AU0001", "유효하지 않은 토큰입니다."),
    AUTH_TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "AU0002", "만료된 토큰입니다."),
    AUTH_REFRESH_TOKEN_INVALID(HttpStatus.UNAUTHORIZED, "AU0003", "유효하지 않은 리프레시 토큰입니다."),
    AUTH_KAKAO_TOKEN_INVALID(HttpStatus.UNAUTHORIZED, "AU0004", "카카오 액세스 토큰이 유효하지 않습니다."),
    AUTH_KAKAO_APP_MISMATCH(HttpStatus.UNAUTHORIZED, "AU0005", "이 토큰은 다른 카카오 앱에서 발급된 토큰입니다."),
    AUTH_KAKAO_USERINFO_FAILED(HttpStatus.BAD_GATEWAY, "AU0006", "카카오 사용자 정보 조회에 실패했습니다."),

    CHALLENGE_NOT_FOUND(HttpStatus.NOT_FOUND, "CH0001", "챌린지를 찾을 수 없습니다."),
    CHALLENGE_PERIOD_INVALID(HttpStatus.BAD_REQUEST, "CH0002", "챌린지 기간은 시작일 이후이고 최대 7일까지 가능합니다."),
    CHALLENGE_NOT_OWNER(HttpStatus.FORBIDDEN, "CH0003", "본인 챌린지가 아닙니다."),
    CHALLENGE_ALREADY_FINISHED(HttpStatus.BAD_REQUEST, "CH0004", "이미 종료된 챌린지입니다."),

    AMOUNT_NOT_FOUND(HttpStatus.NOT_FOUND, "A0001", "지출 기록을 찾을 수 없습니다."),
    AMOUNT_VIDEO_REQUIRED(HttpStatus.BAD_REQUEST, "A0002", "지출 기록에는 영상이 1개 필요합니다."),
    AMOUNT_INVALID_SPEND_VALUE(HttpStatus.BAD_REQUEST, "A0003", "지출 금액은 0보다 커야 합니다."),
    AMOUNT_INVALID_NO_SPEND_VALUE(HttpStatus.BAD_REQUEST, "A0004", "무지출 기록의 금액은 0이어야 합니다."),
    AMOUNT_CATEGORY_CONTENT_REQUIRED(HttpStatus.BAD_REQUEST, "A0005", "지출 기록은 카테고리와 내용이 필요합니다."),

    MEDIA_UPLOAD_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "M0001", "파일 업로드에 실패했습니다."),
    MEDIA_NOT_FOUND(HttpStatus.NOT_FOUND, "M0002", "파일을 찾을 수 없습니다."),

    BADGE_NOT_FOUND(HttpStatus.NOT_FOUND, "B0001", "배지를 찾을 수 없습니다.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
