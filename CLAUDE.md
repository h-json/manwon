# Tenk — Claude 작업 가이드

이 문서는 새 세션이 시작될 때 Claude가 자동으로 읽는 프로젝트 컨텍스트야.
다른 컴퓨터에서 작업을 이어갈 때 가장 먼저 이 파일을 참고할 것.

> **이 문서를 갱신하는 규칙**: 다음 중 하나라도 발생하면 **같은 PR/커밋(또는 동일 대화 턴) 안에서 이 문서도 함께 갱신**할 것.
> - 코드/스키마/설정/도메인 규칙을 수정했고 이 문서와 어긋나거나 새로 적어둘 사항이 생긴 경우
> - **요구사항·기술 스택·아키텍처 결정이 추가·변경된 경우** (예: 클라이언트 프레임워크 결정, 새 외부 의존성 도입, 인증·저장소 방식 변경, 핵심 도메인 정책 변경)
> - 위 결정을 대화에서 합의했지만 아직 코드에 반영되지 않은 경우에도, 결정 자체는 이 문서에 먼저 박아둘 것
>
> 일시적인 진행 상태는 [docs/handoff.md](docs/handoff.md)에, 영구적인 규칙·구조·결정은 여기에.

---

## 프로젝트 개요

- **서비스 컨셉**: "만원 챌린지" — 짧은 영상으로 지출/무지출을 기록하고, 챌린지 기간(시작일 오늘 이후, 최대 30일) 내 목표 금액 안에서 소비하기.
- **대상 클라이언트**: **Flutter 기반 모바일 앱(iOS/Android 단일 코드베이스)**. 브라우저 기반 흐름(서버 사이드 OAuth redirect, 세션 쿠키 등) 대신 모바일 친화적인 토큰 기반 흐름을 사용. 모든 백엔드 변경은 이 전제를 깔고 갈 것.
  - 카카오 로그인: 공식 `kakao_flutter_sdk`로 access token 발급 후 백엔드 `/api/auth/kakao/login`에 전달.
  - 영상 녹화: Flutter `camera` 패키지의 **`ResolutionPreset.low` + 2초 타이머**로 처음부터 저화질·짧게 촬영. ffmpeg 등 후처리 트랜스코딩은 사용하지 않음.
- **현재 단계**: 백엔드 REST API 골격 1차 구현 완료. 통합테스트는 미수행. Flutter 앱은 카카오 로그인 + 챌린지 CRUD 화면까지 완료 (지출 기록 / 영상 녹화 화면은 다음 단계).

## 리포 구조 (모노레포)

```
tenk/                       # 리포 루트 (CLAUDE.md/docs는 양쪽 공통)
├── CLAUDE.md, README.md
├── docs/                   # 핸드오프·스키마 등 (현재는 backend-only)
│   ├── handoff.md
│   └── schema.sql
├── tenk-backend/           # Spring Boot 백엔드 (Gradle 루트)
│   ├── src/main/java/com/hjson/tenk/...
│   ├── build.gradle, settings.gradle
│   ├── gradlew, gradlew.bat, gradle/
│   └── uploads/            # gitignored, 런타임 영상 저장 (`tenk.upload.base-dir` 기본값)
└── tenk_app/               # Flutter 모바일 앱 (iOS/Android 단일 코드베이스, Dart 패키지명 `tenk_app`)
```

- 백엔드 명령(`gradlew`, 빌드, 실행)은 모두 **`tenk-backend/`에서 실행**.
- Flutter 명령(`flutter pub get`, `flutter run`)은 모두 **`tenk_app/`에서 실행**.
- DB 스키마(`mysql ... < docs/schema.sql`)는 **리포 루트에서 실행** (docs는 루트에 있음).
- API 계약을 바꾸면 **백엔드와 앱을 같은 PR에서 함께 갱신**할 것 (모노레포 이점).

## 기술 스택

| 영역 | 선택 |
|---|---|
| 클라이언트(모바일) | **Flutter (Dart)** — `kakao_flutter_sdk`, `camera` |
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
- **카카오 키 두 종류** (같은 카카오 앱에서 발급되는 별개 값):
  - **앱 ID (숫자)**: 백엔드 `tenk.auth.kakao.app-id`. `access_token_info` 응답의 `app_id`와 매칭 검증용. REST API 키 아님.
  - **네이티브 앱 키 (영숫자)**: Flutter 측에서만 사용. **세 곳에 같은 값을 박는다**:
    1. [tenk_app/lib/config/kakao_config.dart](tenk_app/lib/config/kakao_config.dart) — `kakaoNativeAppKey` 상수 (KakaoSdk.init)
    2. [tenk_app/android/app/build.gradle.kts](tenk_app/android/app/build.gradle.kts) — `manifestPlaceholders["kakaoNativeAppKey"]` (URL scheme 주입)
    3. [tenk_app/ios/Runner/Info.plist](tenk_app/ios/Runner/Info.plist) — `CFBundleURLSchemes`의 `kakao{KEY}` (iOS URL scheme)
- **인증 요청**: 클라이언트가 `Authorization: Bearer <AT>` 헤더 부착. `JwtAuthenticationFilter`가 파싱 → `JwtPrincipal(userId)`를 `SecurityContext`에 주입.
- **토큰 갱신**: `POST /api/auth/refresh { refreshToken }`. 사용된 RT는 즉시 `revoked=true`로 회전(rotation) 후 새 AT/RT 발급.
- **로그아웃**: `POST /api/auth/logout` (AT 필요) → 해당 사용자의 모든 RT를 `revoked=true`. AT 자체는 만료 시까지 유효 (블랙리스트 없음). 회원 탈퇴 시에도 동일하게 RT 일괄 무효화.
- **CORS**: **비활성화** (`SecurityConfig`에서 `cors.disable()`). Flutter 네이티브 앱(iOS/Android)만 호출하므로 브라우저 preflight 자체가 없음. 추후 Flutter Web 등 브라우저 클라이언트를 도입하면 `CorsConfigurationSource` 빈으로 origin/method/header를 명시 설정할 것.

### 영상
- 저화질·2초 영상은 **클라이언트가 처음부터 저화질·짧게 녹화**하는 방식 (사후 변환·트랜스코딩 아님). Flutter 기준 `camera` 패키지의 `ResolutionPreset.low` + 2초 타이머로 처리. 백엔드는 업로드받은 파일을 그대로 저장.
- 저장소는 로컬 파일 시스템 (`tenk.upload.base-dir`, 기본 `./uploads`). `.gitignore`에 등록됨.
- **녹화 시 음성은 꺼둠** (`CameraController(enableAudio: false)`). 사유: `RECORD_AUDIO` 런타임 권한 프롬프트를 한 단계 줄이기 위해. 추후 음성이 필요해지면 매니페스트 `RECORD_AUDIO`는 이미 선언돼 있으니 코드에서 `enableAudio: true`로만 바꾸면 됨.
- **업로드 형식**: multipart/form-data로 `request`(application/json) + `video`(video/mp4) 2개 part. dio의 `MediaType`은 dio v5.7+에서 `DioMediaType`으로 재익스포트됨 — 따로 `http_parser`를 의존성에 추가하지 말 것.

### 챌린지
- 한 사용자가 **여러 챌린지 동시 진행 가능**.
- 기간 표현: `start_date` / `end_date` **DATE (양끝 포함)**. 시각 정보 없음. (`Challenge.startDate` / `endDate`)
- 검증 (`Challenge.validatePeriod`): ① `startDate >= today` (오늘 이후만 시작) ② `endDate >= startDate` ③ inclusive 일수 ≤ `MAX_DURATION_DAYS = 30`.
- 상태:
  - **시작 전**: `today < startDate` — 기록 불가
  - **진행 중**: `startDate <= today <= endDate` and `result == null` — 기록 가능
  - **결과 확정 대기**: `today > endDate` and `result == null` — `finalize` 호출 가능
  - **성공/실패**: `result` 설정됨
- 상태 판별 메서드: `isStarted(today)`, `isFinished(today)`, `containsDate(date)`. `ChallengeResponse`는 `started`/`finished` 둘 다 노출.
- 종료 시점에 `result` 컬럼 확정: `SUCCESS`(총지출 ≤ target_amount) / `FAIL`. `NULL`이면 진행 중.
- 확정 트리거는 ① 사용자 호출(`POST /api/challenges/{id}/finalize`) ② 매일 새벽 1시 배치(`BadgeScheduler.dailyReconciliation`) 두 가지.

### 지출(amount)
- **지출 기록**: `category`, `content` NOT BLANK, `amount > 0`, **영상 1개 필수**.
- **무지출 기록**: `is_no_spend = true`, `amount = 0`, `category/content` NULL 허용, **영상 선택**.
- **일시 의미**:
  - `spent_dt` (DATETIME, NOT NULL): 사용자가 고른 "지출이 발생한 일시". **날짜 부분**이 챌린지 기간(`startDate`~`endDate`, 양끝 포함) 안에 있어야 함 (`AMOUNT_DATE_OUT_OF_RANGE`). 기본값은 지금. 배지·집계는 `spentDt.toLocalDate()`를 기준으로 잡는다.
  - `created_dt` (DATETIME, JPA Auditing): 서버가 자동으로 박는 row 생성 시각. 감사용. 도메인 로직에서 직접 쓰지 않는다.
- 챌린지가 시작 전이거나(`CHALLENGE_NOT_STARTED`) 종료된 상태(`CHALLENGE_ALREADY_FINISHED`)에서는 기록 불가.

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

## 패키지 구조 (백엔드)

루트: `tenk-backend/src/main/java/com/hjson/tenk/`

```
com.hjson.tenk
├── TenkApplication.java          # @EnableScheduling, @ConfigurationPropertiesScan
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

## 패키지 구조 (Flutter 앱)

루트: `tenk_app/lib/`

```
lib/
├── main.dart                   # composition root만. 의존성 조립 + Scope 주입 + MaterialApp
├── app/                        # 앱 셸: 라우팅 진입점, 전역 DI, 네비게이터 키
│   ├── navigator_key.dart        # 위젯 트리 밖(예: dio interceptor)에서 라우터 접근용
│   ├── scopes.dart               # AuthScope / ChallengeScope / ... (InheritedWidget DI)
│   └── session_gate.dart         # 토큰 유무에 따라 홈/로그인 분기
├── config/                     # 컴파일 타임 상수 (API base URL, 카카오 키)
├── data/                       # 모든 외부 통신·영속성. 화면에서 직접 import 금지 — Scope를 거쳐서만
│   ├── api/                      # 전송 계층 공용
│   │   ├── dio_client.dart         # rawDio(인증X) + authDio(401 회전 인터셉터 부착)
│   │   ├── auth_interceptor.dart   # single-flight refresh + 1회 재시도
│   │   ├── api_response.dart       # 백엔드 envelope `{success,data,error}` 헬퍼
│   │   ├── api_error.dart          # 서버 에러 → ApiException 변환
│   │   └── auth_api.dart           # /api/auth/* HTTP 호출만
│   ├── auth/                     # 도메인 폴더: 모델 + (필요시) repository + storage
│   │   ├── auth_tokens.dart, token_storage.dart, auth_repository.dart
│   ├── challenge/                # 도메인 폴더: 모델 + api (지금은 repo 불필요)
│   │   ├── challenge.dart, challenge_api.dart
│   └── amount/                   # 지출/무지출 기록 + multipart 영상 업로드
│       ├── amount.dart, amount_api.dart
└── presentation/               # 화면. data 레이어를 Scope로만 호출
    ├── common/                   # 도메인 무관 공용 위젯·헬퍼
    │   ├── async_state.dart        # AsyncStateMixin + AsyncStateView (필수 — 아래 컨벤션 참고)
    │   └── error_view.dart
    ├── login/login_screen.dart
    ├── challenge/
    │   ├── _formatters.dart        # 도메인 내부 공유 (외부 노출 X — 언더스코어 prefix)
    │   ├── widgets/                # 도메인 전용 공용 위젯
    │   │   └── challenge_status.dart
    │   └── *_screen.dart
    └── amount/
        └── amount_record_screen.dart  # 카메라 프리뷰 + 2초 녹화 + 폼 (지출/무지출 토글)
```

### 레이어 규칙 (반드시 지킬 것)
- **`presentation/`에서 `data/api/*Api`를 직접 import 금지.** 항상 `Scope.of(context)`를 거쳐서만 접근. composition root(`main.dart`)에서 주입된 인스턴스만 화면이 본다.
- **`data/`에서 `presentation/` import 금지.** 단방향 의존성.
- **Repository 패턴은 강제하지 않음**: 하나의 도메인이 *여러 출처*(예: 외부 SDK + 백엔드 + storage)를 합쳐야 할 때만 `*_repository.dart`를 만든다. 단일 백엔드 호출만 하는 도메인은 `*_api.dart`만으로 충분. (예: [auth_repository.dart](tenk_app/lib/data/auth/auth_repository.dart)는 카카오 SDK + AuthApi + TokenStorage 3개를 합치므로 가치 있음. challenge는 아직 api만으로 충분.)
- **Scope는 도메인별로 하나씩** `app/scopes.dart`에 추가. Scope 개수가 5개를 넘기는 시점에 Riverpod/Provider 도입을 재검토 (지금은 boilerplate가 그만한 비용을 정당화하지 못함).
- **새 화면 코드가 `import '../../main.dart'` 하면 잘못된 방향.** Scope·SessionGate·navigatorKey는 모두 `app/`에 있다.

## 코딩 컨벤션 — 백엔드

- **컨트롤러는 얇게**, 비즈니스 로직은 서비스에. 엔티티는 정적 팩토리 메서드로 생성하고 invariant 검증.
- **에러는 `BusinessException(ErrorCode.XXX)`로 던지기.** 새 케이스는 `ErrorCode` enum에 추가. 메시지는 한국어.
- **DTO는 record로**. 요청 DTO는 Bean Validation 어노테이션 사용.
- **트랜잭션**: 서비스 클래스는 기본 `@Transactional(readOnly = true)`, 쓰기 메서드만 `@Transactional`.
- **사용자 ID 주입**: 컨트롤러 파라미터에 `@CurrentUserId Long userId` 사용. (내부적으로 `@AuthenticationPrincipal(expression="userId")`)
- **댓글은 최소화.** "왜"가 비자명할 때만 작성. JavaDoc은 정책 문서 역할일 때만 (예: `BadgeGrantService` 상단).
- **새 API를 만들 때**: `@Tag`, `@Operation` 어노테이션을 빠뜨리지 말 것 (Swagger).

## 코딩 컨벤션 — Flutter

- **화면의 비동기 로딩은 `AsyncStateMixin` + `AsyncStateView` 사용**. `FutureBuilder` 금지. 이유: `FutureBuilder`가 새 future로 교체돼도 stale snapshot으로 그리는 케이스가 있어 챌린지 생성/삭제 후 갱신이 누락된 적이 있음. mixin은 `_loading/_data/_error/_loadGen` 4-tuple과 stale-response 가드를 한 곳에 캡슐화한다. 한 화면이 두 종류 이상의 비동기 자원을 다루면 mixin 대신 직접 state를 들 것. ([presentation/common/async_state.dart](tenk_app/lib/presentation/common/async_state.dart))
- **HTTP 응답은 항상 `unwrapData` / `unwrapList` 통과**. 백엔드 envelope 풀이 로직을 도메인마다 복붙하지 말 것. ([data/api/api_response.dart](tenk_app/lib/data/api/api_response.dart))
- **에러는 SnackBar로 노출 시 `toApiException(e).message` 사용**. dio 에러·서버 에러·기타 예외를 일관된 한국어 메시지로 변환.
- **모델은 immutable + `fromJson` 팩토리**. `@immutable` 어노테이션 + `final` 필드. JSON 키는 백엔드 응답 그대로 (snake/camel 변환 X).
- **Navigator push/pop의 generic은 양쪽 모두 명시** (`push<T>(MaterialPageRoute<T>(...))`). push 결과에 의존하지 말고 push 종료 시점에 무조건 새로고침 — 결과 누락 케이스가 있음 ([docs/handoff.md](docs/handoff.md) "함정 — Flutter" 참고).
- **위젯 중복은 즉시 추출**: 두 화면이 같은 위젯을 쓰면 도메인 위젯은 `presentation/<domain>/widgets/`, 도메인 무관 공용 위젯은 `presentation/common/`에. 화면 파일 안에 `_PrivateView` 클래스로 두는 건 그 화면에서만 쓸 때.
- **백엔드의 LocalDateTime 전송은 `Z` 없는 ISO-8601 직접 포맷**. `DateTime.toIso8601String()`은 UTC 변환 시 `Z`가 붙어 백엔드 LocalDateTime 파서를 깨뜨림 ([challenge_api.dart](tenk_app/lib/data/challenge/challenge_api.dart) `_formatLocal` 참고).
- **댓글은 최소화.** "왜"가 비자명할 때만 (예: dio 2개 인스턴스 이유, `_loadGen` 세대 카운터 이유, hide 키워드로 카카오 SDK `AuthApi` 가리기).

## 환경 설정 / 프로파일

- **프로파일 분리**: `application.yaml`(공통) + `application-local.yaml`(로컬 DB 자격증명) + `application-prod.yaml`(prod placeholder).
- **기본 active 프로파일은 `local`** — `application.yaml`의 `spring.profiles.active: local` 기본값. prod 실행은 `--spring.profiles.active=prod`.
- **자격증명은 환경변수 대신 yaml에 직접 박는다.** private 레포 전제. `.gitignore`에서 `application-*.yaml` 라인을 제거해 둘 다 git 추적함.
- **`tenk.auth.jwt`** (secret, accessTokenTtl, refreshTokenTtl, issuer) / **`tenk.auth.kakao.app-id`** — `AuthProperties` 레코드로 바인딩. `secret`은 Base64 인코딩된 HS256 키.
- **`tenk.auth.jwt.secret`은 환경별 profile에서만 정의한다.** 공통 `application.yaml`에는 **의도적으로 비워둠** — fallback이 있으면 prod에 dev 키가 새어나갈 위험. `application-local.yaml`엔 의미 있는 평문(`tenk-local-jwt-secret-key-for-development-12345678`)을 Base64로 인코딩한 dev 키, `application-prod.yaml`엔 `openssl rand -base64 64`로 생성한 512bit 랜덤 키. 두 키는 서로 다른 값이어야 한다 — local 키는 코드/문서에 등장해도 무해하지만 prod 키는 절대 노출 금지. 노출 시 yaml에서 새 키로 교체하면 기존 AT/RT가 모두 즉시 무효화된다.
- 카카오 REST API 키(=`app-id`, 숫자)는 `tenk.auth.kakao.app-id`에 실제 값 박을 예정. 모바일 SDK가 토큰 발급을 담당하므로 server-side `client-secret`은 사실상 불필요.

## 로컬 실행 방법

### 백엔드

```powershell
# 1. DB 준비 (MariaDB) — 리포 루트에서
mysql -u root -p
> CREATE DATABASE tenk DEFAULT CHARACTER SET utf8mb4;
> CREATE USER 'tenk'@'localhost' IDENTIFIED BY '<your-pw>';
> GRANT ALL ON tenk.* TO 'tenk'@'localhost';

# 2. 스키마 적용 (ddl-auto=validate 이므로 필수) — 리포 루트에서
mysql -u tenk -p tenk < docs/schema.sql

# 3. tenk-backend/src/main/resources/application-local.yaml의 datasource.username/password 본인 계정으로 수정

# 4. 실행 (기본 active=local) — tenk-backend/ 디렉토리에서
cd tenk-backend
./gradlew.bat bootRun
# 브라우저: http://localhost:8080/swagger-ui.html
```

### Flutter 앱

```powershell
cd tenk_app
flutter pub get
flutter run    # 연결된 디바이스/에뮬레이터에서 실행
```

> 안드로이드 에뮬레이터는 호스트 백엔드를 `http://10.0.2.2:8080`으로, iOS 시뮬레이터는 `http://localhost:8080`으로 호출.

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
| Flutter 새 도메인 추가 | ① 데이터: `lib/data/<feature>/<feature>.dart`(모델, `@immutable` + `fromJson`) + `<feature>_api.dart`(authDio 주입, `unwrapData`/`unwrapList` 사용). 여러 출처를 합쳐야 하면 `<feature>_repository.dart`도. ② DI: `lib/app/scopes.dart`에 `<Feature>Scope` 추가 + `main.dart`에서 인스턴스 생성·주입. ③ 화면: `lib/presentation/<feature>/<feature>_screen.dart`. 데이터 호출은 `<Feature>Scope.of(context)`로만 |
| Flutter 새 화면의 비동기 로딩 | `AsyncStateMixin<W, T>` + `AsyncStateView<T>` 사용 ([presentation/common/async_state.dart](tenk_app/lib/presentation/common/async_state.dart)). `FutureBuilder` 금지. `fetch()` 오버라이드 + `didChangeDependencies`에서 `ensureLoaded()`. 외부 동작 결과를 즉시 반영하려면 `replaceData(next)`, 그 외 갱신은 `reload()`. 에러는 `toApiException(e).message`로 SnackBar 노출 |
| Flutter 새 공용 위젯 | 두 화면 이상이 같은 위젯을 쓰면 즉시 추출. 도메인 전용은 `presentation/<domain>/widgets/`, 도메인 무관은 `presentation/common/` |

## 미해결/다음 단계

진행 상태와 남은 작업은 [docs/handoff.md](docs/handoff.md) 참고.
