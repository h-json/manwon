# Manwon — Claude 작업 가이드

이 문서는 새 세션이 시작될 때 Claude가 자동으로 읽는 프로젝트 컨텍스트야.
다른 컴퓨터에서 작업을 이어갈 때 가장 먼저 이 파일을 참고할 것.

> **이 문서를 갱신하는 규칙**: 코드/스키마/설정/도메인 규칙을 수정했을 때 이 문서와 어긋나거나 새로 적어둘 사항이 생기면 **같은 PR/커밋 안에서 이 문서도 함께 갱신**할 것. 일시적인 진행 상태는 [docs/handoff.md](docs/handoff.md)에, 영구적인 규칙·구조·결정은 여기에.

---

## 프로젝트 개요

- **서비스 컨셉**: "만원 챌린지" — 짧은 영상으로 지출/무지출을 기록하고, 챌린지 기간(최대 7일) 내 목표 금액 안에서 소비하기.
- **대상 클라이언트**: **모바일 앱(iOS/Android)**. 브라우저 기반 흐름(서버 사이드 OAuth redirect, 세션 쿠키 등) 대신 모바일 친화적인 토큰 기반 흐름을 사용. 모든 백엔드 변경은 이 전제를 깔고 갈 것.
- **현재 단계**: 백엔드 REST API 골격 1차 구현 완료. 카카오 키·DB 연동·통합테스트는 미수행.

## 기술 스택

| 영역 | 선택 |
|---|---|
| 언어/런타임 | Java 21 |
| 프레임워크 | Spring Boot 4.0.6 |
| 영속성 | Spring Data JPA + MariaDB |
| 보안 | Spring Security (stateless) + **자체 JWT (HS256, jjwt)** |
| 인증 방식 | **모바일 SDK가 카카오 access token 발급 → 백엔드가 검증·자체 JWT(AT+RT) 발급**. 세션·쿠키 없음 |
| 마이그레이션 | **JPA `ddl-auto=validate` + `docs/schema.sql` 수동 적용** (Flyway 등 미사용) |
| 파일 저장 | 로컬 파일 시스템 (`./uploads/`, gitignore) |
| API 문서 | springdoc-openapi (`/swagger-ui.html`) |
| 빌드 | Gradle Wrapper |

## 도메인 규칙 (의사결정 합의)

### 인증
- **현재 활성 공급자**: `KAKAO`만. `GOOGLE`/`NAVER`는 enum/`AuthProvider`에는 남아 있으나 실 흐름·코드는 미구현 (추후 동일한 모바일 토큰 교환 방식으로 추가 예정).
- ID/비밀번호 자체 로그인 없음. `user.password` 컬럼은 **제거**, 대신 `provider`, `provider_user_id`, `email`을 사용. `(provider, provider_user_id)`가 unique.
- **로그인 흐름** (모바일 전용):
  1. 모바일 앱이 카카오 SDK로 access token 발급.
  2. `POST /api/auth/kakao/login { accessToken }` 호출.
  3. 백엔드가 `kapi.kakao.com/v1/user/access_token_info`로 **`app_id` 매칭 검증** (다른 앱 토큰 차단) → `/v2/user/me`로 사용자 정보 조회.
  4. 신규면 자동 프로비저닝, 기존이면 닉네임/이메일 갱신.
  5. 자체 JWT **AT(1시간, HS256)** + opaque **RT(랜덤 64자, SHA-256 해시로 DB 저장, 14일)** 발급.
- **인증 요청**: 클라이언트가 `Authorization: Bearer <AT>` 헤더 부착. `JwtAuthenticationFilter`가 파싱 → `JwtPrincipal(userId)`를 `SecurityContext`에 주입.
- **토큰 갱신**: `POST /api/auth/refresh { refreshToken }`. 사용된 RT는 즉시 `revoked=true`로 회전(rotation) 후 새 AT/RT 발급.
- **로그아웃**: `POST /api/auth/logout` (AT 필요) → 해당 사용자의 모든 RT를 `revoked=true`. AT 자체는 만료 시까지 유효 (블랙리스트 없음). 회원 탈퇴 시에도 동일하게 RT 일괄 무효화.

### 영상
- "저화질·2초" 변환은 **클라이언트 책임**. 백엔드는 업로드받은 파일을 그대로 저장.
- 저장소는 로컬 파일 시스템 (`manwon.upload.base-dir`, 기본 `./uploads`). `.gitignore`에 등록됨.

### 챌린지
- 한 사용자가 **여러 챌린지 동시 진행 가능**.
- 기간은 자유 선택, **최대 7일**. 엔티티 생성 시 검증(`Challenge.MAX_DURATION_DAYS`).
- 종료 시점에 `result` 컬럼 확정: `SUCCESS`(총지출 ≤ target_amount) / `FAIL`. `NULL`이면 진행 중.
- 확정 트리거는 ① 사용자 호출(`POST /api/challenges/{id}/finalize`) ② 매일 새벽 1시 배치(`BadgeScheduler.dailyReconciliation`) 두 가지.

### 지출(amount)
- **지출 기록**: `category`, `content` NOT BLANK, `amount > 0`, **영상 1개 필수**.
- **무지출 기록**: `is_no_spend = true`, `amount = 0`, `category/content` NULL 허용, **영상 선택**.
- `created_dt`가 곧 "지출/기록 발생일". 별도 `spent_date` 컬럼 없음.

### 배지
- 단계: `condition_value` = **3 / 7 / 14 / 30**.
- `STREAK`: 매일(지출 또는 무지출 무관) 기록한 **연속 일수**.
- `NO_SPEND`: 그날 기록이 **무지출만** 있는 날의 연속 일수. 같은 날 지출 기록이 끼면 끊김.
- `CHALLENGE_SUCCESS`: `condition_value = 1` 1개만 존재, 챌린지 성공 시 1회 지급.
- **지급 트리거 2종**: 
  - 이벤트: `AmountRecordedEvent`(지출/무지출 기록 후), `ChallengeFinishedEvent`(챌린지 확정 후) — `BadgeEventListener`에서 `AFTER_COMMIT` 처리
  - 배치: 매일 새벽 1시 전체 사용자 재평가 (이벤트 누락 대비)

### 내보내기
- **영상 내보내기(워터마크/오버레이)는 이번 범위에서 제외.**
- 챌린지 결과는 **JSON 반환**만 함 (`GET /api/challenges/{id}/export`). 화면 구성은 클라이언트 몫.

## 패키지 구조

```
com.hjson.manwon
├── ManwonApplication.java          # @EnableScheduling, @ConfigurationPropertiesScan
├── common
│   ├── api/ApiResponse.java        # 공통 응답 포맷 {success, data, error}
│   ├── config/                     # JpaAuditing, OpenApi, *Properties
│   └── exception/                  # ErrorCode, BusinessException, GlobalExceptionHandler
├── security/                       # SecurityConfig (STATELESS) + JwtTokenProvider/JwtAuthenticationFilter
│                                   # + JwtPrincipal + KakaoTokenVerifier + @CurrentUserId
└── domain
    ├── auth/        (AuthController, AuthService, RefreshToken, RefreshTokenRepository, AuthTokens, dto/)
    ├── user/        (entity, repo, service, controller, dto/, AuthProvider)
    ├── challenge/   (+ ChallengeExportService, event/ChallengeFinishedEvent)
    ├── amount/      (+ event/AmountRecordedEvent)
    ├── media/       (MediaFile, LocalFileStorage, MediaController)
    └── badge/       (Badge, UserBadge, BadgeGrantService, BadgeEventListener, BadgeScheduler)
```

## 코딩 컨벤션

- **컨트롤러는 얇게**, 비즈니스 로직은 서비스에. 엔티티는 정적 팩토리 메서드로 생성하고 invariant 검증.
- **에러는 `BusinessException(ErrorCode.XXX)`로 던지기.** 새 케이스는 `ErrorCode` enum에 추가. 메시지는 한국어.
- **DTO는 record로**. 요청 DTO는 Bean Validation 어노테이션 사용.
- **트랜잭션**: 서비스 클래스는 기본 `@Transactional(readOnly = true)`, 쓰기 메서드만 `@Transactional`.
- **사용자 ID 주입**: 컨트롤러 파라미터에 `@CurrentUserId Long userId` 사용. (내부적으로 `@AuthenticationPrincipal(expression="userId")`)
- **댓글은 최소화.** "왜"가 비자명할 때만 작성. JavaDoc은 정책 문서 역할일 때만 (예: `BadgeGrantService` 상단).
- **새 API를 만들 때**: `@Tag`, `@Operation` 어노테이션을 빠뜨리지 말 것 (Swagger).

## 환경 설정 / 프로파일

- **프로파일 분리**: `application.yaml`(공통) + `application-local.yaml`(로컬 DB 자격증명) + `application-prod.yaml`(prod placeholder).
- **기본 active 프로파일은 `local`** — `application.yaml`의 `spring.profiles.active: local` 기본값. prod 실행은 `--spring.profiles.active=prod`.
- **자격증명은 환경변수 대신 yaml에 직접 박는다.** private 레포 전제. `.gitignore`에서 `application-*.yaml` 라인을 제거해 둘 다 git 추적함.
- **`manwon.auth.jwt`** (secret, accessTokenTtl, refreshTokenTtl, issuer) / **`manwon.auth.kakao.app-id`** — `AuthProperties` 레코드로 바인딩. `secret`은 Base64 인코딩된 HS256 키.
- 카카오 REST API 키(=`app-id`, 숫자)는 `manwon.auth.kakao.app-id`에 실제 값 박을 예정. 모바일 SDK가 토큰 발급을 담당하므로 server-side `client-secret`은 사실상 불필요.

## 로컬 실행 방법

```powershell
# 1. DB 준비 (MariaDB)
mysql -u root -p
> CREATE DATABASE manwon DEFAULT CHARACTER SET utf8mb4;
> CREATE USER 'manwon'@'localhost' IDENTIFIED BY '<your-pw>';
> GRANT ALL ON manwon.* TO 'manwon'@'localhost';

# 2. 스키마 적용 (ddl-auto=validate 이므로 필수)
mysql -u manwon -p manwon < docs/schema.sql

# 3. application-local.yaml의 datasource.username/password를 본인 DB 계정으로 수정

# 4. 실행 (기본 active=local)
./gradlew.bat bootRun
# 브라우저: http://localhost:8080/swagger-ui.html
```

## 위치별 책임 (요약)

| 변경 위치 | 동시에 챙겨야 할 곳 |
|---|---|
| 엔티티 컬럼 추가 | `docs/schema.sql` 수동 동기화 (validate 모드라 안 맞으면 부팅 실패) |
| 새 도메인 추가 | 패키지 분리 (`domain/<name>/`), `ErrorCode`에 도메인 prefix 코드 추가 |
| 새 이벤트 추가 | `*Event` record는 도메인의 `event/` 하위에, 리스너는 소비자 도메인에 |
| 로그인 공급자 추가 | 공급자별 토큰 검증기(현 `KakaoTokenVerifier` 패턴) + `AuthService`에 분기 + `AuthProvider` enum 추가 + 신규 엔드포인트 `POST /api/auth/<provider>/login`. **브라우저 OAuth redirect 흐름은 사용하지 않음** (모바일 SDK + 토큰 교환 전제) |
| 파일 업로드 | 항상 `LocalFileStorage.store(file, subdir)`을 거치기. 경로를 직접 조립하지 말 것 |
| 환경별로 다른 값 추가 | 공통은 `application.yaml`, 환경별 override는 `application-{local,prod}.yaml`. prod placeholder는 TODO 주석 유지 |
| 보호된 신규 엔드포인트 추가 | 기본적으로 인증 필요 (`SecurityConfig.PERMIT_ALL`에 없으면 자동 보호). 컨트롤러는 `@CurrentUserId Long userId`로 사용자 식별 |

## 미해결/다음 단계

진행 상태와 남은 작업은 [docs/handoff.md](docs/handoff.md) 참고.
