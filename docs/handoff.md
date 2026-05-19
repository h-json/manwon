# Handoff — Tenk

> 다른 컴퓨터/세션에서 이 작업을 이어받는 사람(또는 미래의 나)을 위한 인계 노트.
> 영구적인 규칙·결정은 [../CLAUDE.md](../CLAUDE.md)에 있고, 이 문서는 **현재 진행 상태와 다음 할 일**만 기록함.

마지막 갱신: 2026-05-19 (Swagger 인증 시나리오 1·2·3 통과 + 단위 테스트 49개 그린)

---

## 새 컴퓨터에서 시작하는 순서

> 리포 구조는 모노레포: `tenk-backend/`(Spring Boot) + `tenk_app/`(Flutter). 자세한 건 [../CLAUDE.md](../CLAUDE.md) "리포 구조" 섹션.

1. 저장소 클론 후 IntelliJ/VS Code 등으로 열기. JDK 21 확인. (Flutter 작업까지 한다면 Flutter SDK도)
2. MariaDB 준비 → `docs/schema.sql` 적용. 리포 루트에서 `mysql -u tenk -p tenk < docs/schema.sql`.
3. `tenk-backend/src/main/resources/application-local.yaml`의 `spring.datasource.username/password`를 본인 로컬 계정으로 수정.
4. **카카오 앱 등록**:
   - https://developers.kakao.com → 내 애플리케이션 추가
   - 제품 설정 → **카카오 로그인 활성화**. (모바일 SDK가 토큰을 받아오므로 Redirect URI는 백엔드와 무관)
   - 동의 항목에서 `프로필 정보(닉네임)`, `카카오계정(이메일)` 활성화
   - 앱 키의 **앱 ID(숫자)**를 `tenk-backend/src/main/resources/application.yaml`의 `tenk.auth.kakao.app-id`에 박기 (server-side `access_token_info`의 `app_id`와 매칭 검증용)
5. 백엔드 실행: `cd tenk-backend && ./gradlew.bat bootRun` → `http://localhost:8080/swagger-ui.html`
6. 백엔드 테스트: `cd tenk-backend && ./gradlew.bat test` (단위 테스트 49개 그린 상태가 기대값)
7. **Flutter 앱 셋업** (앱 작업까지 할 거면):
   - 새 머신의 `~/.android/debug.keystore`에서 키해시 추출:
     `keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android | openssl sha1 -binary | openssl base64` (Git Bash). PowerShell `Get-FileHash` 안 됨 — [[reference-kakao-android-keyhash]] 참고.
   - 출력값을 카카오 디벨로퍼스 → Tenk 앱 → 플랫폼 → Android의 키해시 목록에 **추가** 등록 (기존 머신 키해시는 그대로 두고 추가). 한 플랫폼에 여러 해시 등록 가능.
   - `cd tenk_app && flutter pub get && flutter run`. 에뮬레이터에서 글자가 안 보이면 [[reference-flutter-android-impeller-text-glitch]] 참고.
8. Claude 세션 시작: 리포 루트에서 `claude` (CLAUDE.md 자동 로딩됨). 첫 메시지로 *"docs/handoff.md 읽고 이어서 진행해줘"* 라고 말하면 컨텍스트 빠르게 복구.

---

## 완료된 것 (요약)

> 디테일은 git log/blame에 있음. 여기엔 "어디까지 왔는지" + "코드에 안 보이는 결정"만.

- ✅ **백엔드 골격**: 프로젝트 스캐폴딩, JPA 엔티티 7종 + Repository, 공통 응답/에러 처리, REST API(User/Challenge/Amount/Media/Badge), 영상 업로드(지출 필수/무지출 선택), Swagger UI, JPA Auditing.
- ✅ **인증**: 모바일 카카오 SDK + 자체 JWT(AT 1시간/RT 14일). `KakaoTokenVerifier`가 `access_token_info`로 `app_id` 매칭 검증. RT는 SHA-256 해시로 DB 저장, 회전 시 즉시 revoke. **Swagger 시나리오 1·2·3 통과 (2026-05-19, curl + DB 검증)**:
  - RT 회전 정상 — 한 번 쓴 RT는 401 + AU0003
  - logout 일괄 무효화 — DB의 그 user_id RT 전부 `is_revoked=1`
  - 만료 AT 401 + `AU0002`(EXPIRED) ≠ `AU0001`(INVALID) 코드 구분 확인
- ✅ **JWT secret 환경별 분리**: 공통 `application.yaml`에 secret 안 둠 (prod에 dev 키 누수 방지). `application-{local,prod}.yaml` 각각 별도 키. 키 노출 시 대응 → 아래 "알려진 주의사항" 참고.
- ✅ **배지 자동 지급**: 이벤트(`AmountRecordedEvent`/`ChallengeFinishedEvent` AFTER_COMMIT) + 매일 새벽 1시 배치 재평가. 단위 테스트로 정책 커버, **실제 이벤트 propagation E2E는 미검증** (아래 §1).
- ✅ **챌린지 결과 export**: `GET /api/challenges/{id}/export` — 일별/카테고리별 JSON 집계.
- ✅ **CORS 비활성화**: Flutter 네이티브 앱만 대상 (브라우저 preflight 없음). 추후 웹 도입 시 `CorsConfigurationSource` 빈 추가.
- ✅ **Spring Boot 4 + Jackson v3 마이그레이션**: `com.fasterxml.jackson.databind.ObjectMapper` → `tools.jackson.databind.ObjectMapper`. 어노테이션은 그대로.

- ✅ **Flutter 앱**: 카카오 로그인 + 챌린지 CRUD + 지출/무지출 기록 + 2초 영상 녹화·업로드(`camera` ResolutionPreset.low + enableAudio:false) + 일시 picker + 잔액 반영 + 삭제 + finalize. **에뮬레이터 E2E 통과 (2026-05-19)**. 구조는 `lib/app/`(셸) + `lib/data/`(api/repository) + `lib/presentation/`(화면) 3층. 컨벤션은 [../CLAUDE.md](../CLAUDE.md) "패키지 구조 (Flutter 앱)" + "코딩 컨벤션 — Flutter" 참고.
- ✅ **카카오 키 박힘**: 네이티브 앱 키 `589078d3c7daa590c71d9a6e77080b18` 3곳 (kakao_config.dart + Android build.gradle + iOS Info.plist), 백엔드 `tenk.auth.kakao.app-id = 1459747`. Android 키해시 `Dt3/ajH81vV0Ex78dS1ACaqelWc=` (이 머신 debug.keystore 기준). 새 머신은 [[reference-kakao-android-keyhash]] 절차로 재등록.

- ✅ **백엔드 단위 테스트 49개 그린** (2026-05-19, Mockito + AssertJ). `./gradlew.bat test` 통과. 6개 파일:
  - [ChallengeTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/challenge/ChallengeTest.java) (10) — 30일/시작일 과거/역순/null, isStarted·isFinished·containsDate 경계
  - [AmountTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/amount/AmountTest.java) (9) — spend invariant, noSpend, update 분기
  - [ChallengeServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/challenge/ChallengeServiceTest.java) (7) — loadOwned, finalize SUCCESS/FAIL/이미확정/미종료
  - [AmountServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/amount/AmountServiceTest.java) (6) — 종료/미시작 거부, 영상 필수, happy path
  - [BadgeGrantServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeGrantServiceTest.java) (8) — STREAK 폴백·끊김, NO_SPEND 끊김, CHALLENGE_SUCCESS 분기
  - [AuthServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/auth/AuthServiceTest.java) (9) — kakaoLogin/refresh/logout 전 분기
  - **결정 1 — invariant 우회**: `LocalDate.now()`가 정적이라 "종료된 챌린지" 상태는 `ReflectionTestUtils.setField(c, "endDate", today.minusDays(1))`로 사후 박음. 도메인 객체는 invariant를 거친 진짜 객체 유지. 두 곳에서만 쓰니 헬퍼화 안 함 (3번째 등장 시 유틸 추출).
  - **결정 2 — Mockito strictness**: Badge/Auth 테스트는 `@MockitoSettings(strictness = LENIENT)` (케이스별 stub 조합 다양). 나머지는 STRICT 유지.

---

## 남은 일 (우선순위 순)

### 1. 배지 자동 지급 E2E (다음 세션 1순위)
- 단위 테스트는 정책을 커버하지만 **실제 이벤트 propagation(`AFTER_COMMIT`) + 배치(@Scheduled cron) 동작은 미검증**.
- 검증 시나리오:
  - **NO_SPEND 3단계**: 진행 중 챌린지에서 무지출만 3일 연속 → DB `user_badge`에 `(user_id, badge_id)` 행이 새로 생기는지. 단, 같은 날 시각만 다르게 여러 무지출 기록해도 1일로 카운트 (Set 기반).
  - **CHALLENGE_SUCCESS**: 챌린지 종료 후 `POST /api/challenges/{id}/finalize` → `CHALLENGE_SUCCESS` 1단계 1회 지급.
  - **배치 재평가**: 이벤트가 누락된 케이스 보강 — 새벽 1시 `BadgeScheduler.dailyReconciliation` (테스트 시 수동 호출 가능하게 빼야 할 수도).
- 검증 방법: 챌린지 기간을 짧게 (예: 시작=오늘, 종료=오늘+2) 만들고 `spent_dt`를 직접 박아서 (Swagger의 `request.dateTime` 필드) 3일치 무지출 생성. 그 후 `GET /api/badges/me` 또는 DB `select * from user_badge where user_id = N` 확인.
- 참고: Flutter에는 **배지 표시 화면이 아직 없음** — DB 또는 Swagger로 확인. (배지 화면 자체는 §3 앱 UX로 분리)

### 2. 통합 테스트 (단위 ✅, 통합은 후속)
- 단위 테스트가 잡지 못하는 영역:
  - **`AmountRepository.findUserAmountsBetween` 경계** — datetime `[from, toExclusive)` 구간. `@DataJpaTest` + Testcontainers MariaDB 권장 (H2는 SQL 방언 차이 함정 — `DATETIME` vs `TIMESTAMP`, boolean 컬럼).
  - **`BadgeEventListener` AFTER_COMMIT** — 트랜잭션 커밋 후 실제로 배지 평가가 도는지 (§1과 일부 겹침).
  - **`@WebMvcTest` 인증 필터** — 헤더 없을 때 401, 만료 AT 401 + 코드, 정상 AT 200. Swagger 시나리오 1·2·3을 자동화하는 셈.
- ⚠️ [TenkApplicationTests.java](../tenk-backend/src/test/java/com/hjson/tenk/TenkApplicationTests.java)는 Spring Initializr 기본 `@SpringBootTest contextLoads`. **로컬 DB가 떠 있어야 통과** (`ddl-auto=validate` + MariaDB 접속). CI 도입 시점에 ① Testcontainers ② test 프로파일 + H2 ③ 이 테스트 삭제·치환 중 결정 필요.

### 3. 앱 UX 다듬기
- **배지 화면** — `GET /api/badges/me` 호출 + 단계별 그리드/리스트. §1 배지 E2E 검증을 사용자가 눈으로 확인할 수 있게 됨.
- **챌린지 결과 화면** — `GET /api/challenges/{id}/export` 활용. 일별/카테고리별 막대 또는 도넛.
- **녹화 영상 미리보기** — 현재는 체크 아이콘만. `video_player` 패키지 추가하면 미리보기 가능 (MVP 범위 밖).
- **실기기 테스트** — `--dart-define=API_BASE_URL=http://192.168.x.x:8080`로 같은 Wi-Fi의 PC IP 주입. 에뮬레이터와 카메라 동작이 미묘하게 다름.

### 4. 페이지네이션 / 정렬
- `/api/challenges`, `/api/challenges/{id}/amounts`가 전체 목록 반환 중. `Pageable` 도입 시점 결정 (지금은 사용자당 챌린지 수가 적어 무방).

### 5. Google / Naver 로그인 추가 (예정)
- 동일 패턴: `GoogleTokenVerifier` / `NaverTokenVerifier` + `AuthService`에 분기 + `POST /api/auth/google/login` / `/naver/login`. **브라우저 redirect 흐름은 사용하지 않음** (모바일 SDK 전제).

### 6. 운영 고려사항 (필요해지면)
- **영상 저장소 S3/MinIO 이전** — `LocalFileStorage`를 인터페이스로 추출 후 구현체 분리.
- **영상 워터마크** (날짜·잔액 오버레이) — 추후 FFmpeg 도입 시 별도 서비스.
- **AT 강제 무효화(블랙리스트)** — 필요 시 Redis. 현재는 AT 만료 시간(1시간)에 의존.

---

## 알려진 주의사항 / 함정

### 백엔드
- **DDL과 엔티티가 어긋나면 부팅 실패** (`ddl-auto=validate`). 컬럼·인덱스 추가 시 `docs/schema.sql`도 같이 수정 후 DB에 적용.
- **`BadgeGrantService.consecutiveStreakEndingOn`은 "오늘 기록이 없으면 어제 기준"** 까지만 봐줌. 이틀 이상 비면 streak=0. 의도된 동작.
- **`@CurrentUserId`가 비인증 요청에서는 null**. `SecurityConfig.PERMIT_ALL`에 새 경로 추가하는데 그 경로에서 `@CurrentUserId`를 받으면 NPE. 인증 필요 경로면 PERMIT_ALL에 넣지 말 것.
- **`JwtAuthenticationFilter`에서 토큰 invalid/expired는 401을 직접 응답** (Bearer 헤더가 *있을 때만*). 헤더가 아예 없으면 그대로 통과 + `AuthenticationEntryPoint`가 401 처리.
- **AT는 stateless** — 로그아웃해도 AT 만료 시간까지 유효. 즉시 무효화 필요하면 RT만 revoke하면 다음 갱신 시 거부됨 (Swagger 시나리오 2로 확인됨).
- **JWT secret 노출 시 대응**: `openssl rand -base64 64`로 새 키 생성 → `application-prod.yaml`의 `tenk.auth.jwt.secret` 교체 → 재부팅. 서명 검증 실패로 기존 AT/RT 즉시 거부. 별도 블랙리스트/Redis 필요 없음.

### Flutter
- **목록/상세 화면의 비동기 데이터는 `AsyncStateMixin` + `AsyncStateView` 사용**, `FutureBuilder` 금지 ([presentation/common/async_state.dart](../tenk_app/lib/presentation/common/async_state.dart)). 한 화면이 두 종류 이상의 비동기 자원을 다루면 mixin 대신 직접 state.
- **Navigator push/pop의 generic은 양쪽 모두 명시.** `MaterialPageRoute<T>(builder: ...)`로 T를 박지 않으면 result가 null로 빠지는 경우. push 종료 시점에 무조건 refresh하는 패턴이 안전.
- **에뮬레이터에서 텍스트가 첫 프레임에 안 보이고 화면을 움직이면 나타나면** [[reference-flutter-android-impeller-text-glitch]] — Impeller 텍스트 atlas 버그. `flutter run --no-enable-impeller`로 검증.
- **매니페스트(`AndroidManifest.xml`) 변경은 hot reload로 반영 안 됨.** 콜드 부팅(`q` → `flutter run`) 또는 hot restart(`R`).
- **카카오 키해시는 머신마다 다름.** 새 머신 [[reference-kakao-android-keyhash]] 절차로 재등록.

---

## 옮겨야 하는 비-git 자산

- **카카오 디벨로퍼스 계정 접근** — 새 머신에서 debug.keystore가 달라 새 키해시 등록 필요. 카카오 앱 ID 자체는 yaml에 박혀 git 추적되지만 콘솔에서 키해시 추가는 사람 작업.
- DB 비밀번호 (지금은 `application-local.yaml`에 박혀 git 추적 중)
- prod JWT secret (현재 `application-prod.yaml`에 박혀 있으나 실제 prod 배포 전 별도 키로 교체 필요)
- (선택) MariaDB 데이터 — 새 환경에서 `schema.sql` 다시 적용해도 무방하면 불필요
- (선택) `tenk-backend/uploads/` 디렉토리 — 이번 머신 영상이 필요 없으면 무시
- (참고) `~/.android/debug.keystore`는 머신별로 다른 게 정상 — Android Studio가 새로 만들어줌. 새 키스토어 → 새 키해시 → 카카오 디벨로퍼스에 추가 등록.
