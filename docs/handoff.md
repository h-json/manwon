# Handoff — Tenk 백엔드

> 다른 컴퓨터/세션에서 이 작업을 이어받는 사람(또는 미래의 나)을 위한 인계 노트.
> 영구적인 규칙·결정은 [../CLAUDE.md](../CLAUDE.md)에 있고, 이 문서는 **현재 진행 상태와 다음 할 일**만 기록함.

마지막 갱신: 2026-05-18 (오후 — Flutter 챌린지 CRUD 화면)

---

## 새 컴퓨터에서 시작하는 순서

> 리포 구조는 모노레포: `tenk-backend/`(Spring Boot) + `tenk_app/`(Flutter). 자세한 건 [../CLAUDE.md](../CLAUDE.md) "리포 구조" 섹션.

1. 저장소 클론 후 IntelliJ/VS Code 등으로 열기. JDK 21 확인. (Flutter 작업까지 한다면 Flutter SDK도)
2. MariaDB 준비 → `docs/schema.sql` 적용 (CLAUDE.md '로컬 실행 방법' 참고). 리포 루트에서 `mysql -u tenk -p tenk < docs/schema.sql`.
3. `tenk-backend/src/main/resources/application-local.yaml`의 `spring.datasource.username/password`를 본인 로컬 계정으로 수정.
4. **카카오 앱 등록**:
   - https://developers.kakao.com → 내 애플리케이션 추가
   - 제품 설정 → **카카오 로그인 활성화**. (모바일 SDK가 토큰을 받아오므로 Redirect URI는 백엔드와 무관)
   - 동의 항목에서 `프로필 정보(닉네임)`, `카카오계정(이메일)` 활성화
   - 앱 키의 **앱 ID(숫자)**를 `tenk-backend/src/main/resources/application.yaml`의 `tenk.auth.kakao.app-id`에 박기 (server-side `access_token_info`의 `app_id`와 매칭 검증용)
5. 백엔드 실행: `cd tenk-backend && ./gradlew.bat bootRun` → `http://localhost:8080/swagger-ui.html`
6. Claude 세션 시작: 리포 루트에서 `claude` (CLAUDE.md 자동 로딩됨). 첫 메시지로 *"docs/handoff.md 읽고 이어서 진행해줘"* 라고 말하면 컨텍스트 빠르게 복구.

## 완료된 것

- [x] 프로젝트 스캐폴딩 (의존성, application.yaml, gitignore)
- [x] 스키마 정의 (`docs/schema.sql`, 배지 마스터 시드 9건 + `refresh_token` 테이블 포함)
- [x] 공통 응답/에러 처리 (`ApiResponse`, `ErrorCode`, `GlobalExceptionHandler`)
- [x] JPA 엔티티 7종 + Repository (User, Challenge, Amount, MediaFile, Badge, UserBadge, RefreshToken)
- [x] **인증: 모바일 카카오 SDK + 자체 JWT(AT/RT)** — `KakaoTokenVerifier`, `JwtTokenProvider`, `JwtAuthenticationFilter`, `AuthService`, `AuthController(/api/auth/kakao/login, /refresh, /logout)`, 사용자 자동 프로비저닝
- [x] User/Challenge/Amount/Media/Badge REST API
- [x] 영상 업로드 (지출 시 필수, 무지출 시 선택), 다운로드/스트리밍 엔드포인트
- [x] 배지 자동 지급 — 이벤트 트리거 + 매일 새벽 1시 배치 재검증
- [x] 챌린지 결과 내보내기 (JSON: 일별/카테고리별 집계)
- [x] Swagger UI (`/swagger-ui.html`)
- [x] `./gradlew.bat compileJava` 통과 확인 (런타임은 아직 미검증)
- [x] DB 연결: `Tenk` 로컬 계정 + `docs/schema.sql` 적용 완료 (모든 테이블 비어 있음)
- [x] 모노레포 재구조화: 백엔드 → `tenk-backend/`, Flutter 자리 `tenk_app/` 확보 (Flutter 스캐폴딩 전)
- [x] CORS 비활성화 (Flutter 네이티브 앱만 대상)
- [x] **백엔드 부팅 검증 (`./gradlew.bat bootRun` 통과)**. Spring Boot 4.0이 Jackson v2→v3로 올라가면서 `ObjectMapper` 패키지가 바뀐 이슈 발견·해결: `com.fasterxml.jackson.databind.ObjectMapper` → `tools.jackson.databind.ObjectMapper` (annotation `com.fasterxml.jackson.annotation.*`는 그대로). [JwtAuthenticationFilter](../tenk-backend/src/main/java/com/hjson/tenk/security/JwtAuthenticationFilter.java) + [SecurityConfig](../tenk-backend/src/main/java/com/hjson/tenk/security/SecurityConfig.java) 임포트만 갱신.
- [x] Flutter 카카오 로그인 코드/설정 1차 구현 — 아래 "1. Flutter 앱 초기 구성" 참고.
- [x] **카카오 로그인 안드로이드 매니페스트 클래스명 수정** — `com.kakao.sdk.flutter.AuthCodeCustomTabsActivity`(존재하지 않는 이름) → `com.kakao.sdk.flutter.auth.AuthCodeHandlerActivity`(SDK 2.x 실제 클래스, 서브패키지 `.auth.` 주의). `tools:node="merge"`로 SDK가 이미 선언한 액티비티에 URL scheme intent-filter만 병합. `<manifest>`에 `xmlns:tools` 추가. [AndroidManifest.xml](../tenk_app/android/app/src/main/AndroidManifest.xml). 펍 캐시 SDK 매니페스트 + `AuthCodeHandlerActivity.kt`의 `onNewIntent` 로직 둘 다 cross-check 함. **에뮬레이터에서 끝까지 도는지 E2E 검증은 미수행** (사용자가 다음에 `flutter run` 콜드 부팅 후 확인 예정).
- [x] **Flutter 챌린지 CRUD 화면** (2026-05-18 오후). 홈을 [ChallengeListScreen](../tenk_app/lib/presentation/challenge/challenge_list_screen.dart)으로 교체 (기존 `home/home_screen.dart` 삭제). [ChallengeCreateScreen](../tenk_app/lib/presentation/challenge/challenge_create_screen.dart)에서 시작/종료 DatePicker + 7일 제한 + 목표 금액 입력. [ChallengeDetailScreen](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart)에서 잔액·진행률 표시 + `awaitsFinalize`일 때 결과 확정 버튼 + 삭제. 데이터 레이어: [Challenge](../tenk_app/lib/data/challenge/challenge.dart) 모델 + [ChallengeApi](../tenk_app/lib/data/challenge/challenge_api.dart) (POST/GET/DELETE/finalize). 공통 에러 매핑 [api_error.dart](../tenk_app/lib/data/api/api_error.dart) — 백엔드 `ApiResponse.error.message`를 SnackBar에 그대로 노출. `main.dart`에 `ChallengeScope` InheritedWidget 추가. `flutter analyze` 0 issues.

## 남은 일 (우선순위 순)

### 1. Flutter 앱 초기 구성 (tenk_app/) — 거의 완료, E2E 검증만 남음
- ✅ 스캐폴딩 (`flutter create --org com.hjson --project-name tenk_app --platforms android,ios .`). Android applicationId / iOS bundle ID 모두 `com.hjson.tenk_app`.
- ✅ 의존성: `kakao_flutter_sdk_user`, `dio`, `flutter_secure_storage`, `camera`.
- ✅ 카카오 키·앱ID 박힘:
  - Tenk 네이티브 앱 키 `589078d3c7daa590c71d9a6e77080b18` — `lib/config/kakao_config.dart` + `android/app/build.gradle.kts` manifestPlaceholders + `ios/Runner/Info.plist` CFBundleURLSchemes 3곳.
  - 백엔드 `tenk.auth.kakao.app-id = 1459747`.
- ✅ 카카오 디벨로퍼스 설정: Tenk 키 카드에 Android 패키지 `com.hjson.tenk_app` + 키 해시 **`Dt3/ajH81vV0Ex78dS1ACaqelWc=`** (이 머신 `~/.android/debug.keystore` 기준, 2026-05-18 정정) + iOS Bundle ID 등록 완료. 카카오 로그인 활성화 + 동의항목 설정 완료.
  - 키해시 추출은 반드시 카카오 공식 명령으로: `keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android | openssl sha1 -binary | openssl base64` (Git Bash). PowerShell `Get-FileHash` 등 다른 방법은 키스토어 파일 자체의 해시를 내서 `kakao_flutter_sdk`가 런타임에 보내는 값과 일치하지 않음 — 과거에 잘못된 값(`ZahB4Kbdi4ADME+cCOe+PAsx7rI=`)을 등록해서 "invalid android key hash"가 났음.
  - 새 머신에서 빌드하거나 release 키스토어를 만들면 해당 키스토어 기준 해시도 별도로 추가 등록해야 함 (한 플랫폼에 여러 해시 등록 가능).
- ✅ Android 네이티브: `network_security_config.xml`(10.0.2.2 cleartext 허용) + INTERNET/ACCESS_NETWORK_STATE 권한 + minSdk 21 보장.
- ✅ iOS 네이티브 (Mac 없어서 빌드 미검증): LSApplicationQueriesSchemes + CFBundleURLSchemes + 카메라/마이크 권한 설명.
- ✅ Dart 구조: `lib/config/{kakao_config,api_config}.dart` + `lib/data/api/{dio_client,auth_api,auth_interceptor,api_error}.dart` + `lib/data/auth/{auth_tokens,token_storage,auth_repository}.dart` + `lib/data/challenge/{challenge,challenge_api}.dart` + `lib/presentation/{login,challenge}/*` + `main.dart` 라우팅 (AuthScope + ChallengeScope InheritedWidget + _SessionGate). 401 시 단일 in-flight refresh + 1회 재시도, refresh 실패 시 자동 로그아웃.
- ✅ Android 에뮬레이터에서 앱 부팅 + 로그인 화면 진입 확인.
- ✅ 안드로이드 매니페스트 Kakao 액티비티 클래스명 수정 완료 (위 "완료된 것" 마지막 항목).
- ✅ E2E 통과: 카카오 로그인 → 백엔드 교환 → 홈 진입 (2026-05-18).
- 🟡 남은 일:
  - **다음 세션 1순위: 지출 기록 화면 + 영상 녹화/업로드.** `camera` 패키지로 `ResolutionPreset.low` + 2초 타이머 녹화 → multipart 업로드 (`request` JSON + `video` 파일 2개 part)로 `POST /api/challenges/{id}/amounts` 호출. 무지출 토글이 켜진 경우 영상 선택, 꺼진 경우 필수. UI 상 ChallengeDetailScreen 하단 placeholder를 "지출 기록하기 / 무지출 기록하기" 버튼 + 기록 리스트로 교체.
  - 카메라 권한 Android 매니페스트 추가 (`<uses-permission android:name="android.permission.CAMERA"/>` + `<uses-feature>`).
  - 실기기 테스트: 같은 Wi-Fi의 PC IP를 `--dart-define=API_BASE_URL=http://192.168.x.x:8080`로 주입.
  - (참고) 동의 화면에 "맞춤형 광고 행태정보 처리" 항목이 보임 — 카카오 플랫폼 강제 항목이라 개발자가 끌 수 없음. 한 번 선택하면 다음 로그인부터 안 뜸. 우리 백엔드는 무관.

### 2. 백엔드 인증 흐름 추가 검증 (E2E 통과 후)
- ✅ 앱 ID 박힘 (1459747), 백엔드 부팅 OK.
- ✅ Flutter 카카오 로그인 → 백엔드 교환 → AT/RT 발급 → 홈 진입 동선 통과 (2026-05-18).
- 🟡 별도 검증 필요 (앱에서 자동 발생하기 어려움). **Swagger UI 시나리오** — `http://localhost:8080/swagger-ui.html`에서 Authorize 버튼에 `Bearer <AT>` 입력 후 진행:
  1. **RT 회전 정상**: `/api/auth/kakao/login`으로 받은 RT₁을 `/api/auth/refresh`에 한 번 호출 → 200 + AT₂/RT₂ 응답. 같은 RT₁로 두 번째 `/refresh` → **401**(`AUTH_REFRESH_TOKEN_INVALID`)이 떠야 정상. RT₂로 호출하면 또 회전 → AT₃/RT₃.
  2. **logout RT 일괄 무효화**: AT(아무거나 살아있는 것)로 `/api/auth/logout` 호출 → 200. 직전 가장 최신 RT로 `/refresh` 시도 → **401**. DB에서 `select revoked, count(*) from refresh_token where user_id = ? group by revoked` 했을 때 그 사용자 RT 전부 `revoked=1`인지.
  3. **만료 AT는 401 + 코드 구분**: AT 유효 기간이 1시간이라 그냥은 만료 안 됨. 빠르게 확인하려면 `application-local.yaml`에 임시로 `tenk.auth.jwt.access-token-ttl: PT10S` 박고 재부팅 → 로그인 후 10초 대기 → 보호 자원 호출 → 401 + `error.code = AUTH_TOKEN_EXPIRED`(`AUTH_TOKEN_INVALID`가 아니라). 확인 끝나면 TTL 원복.
  4. **stateless AT의 의도된 제약**: logout 후에도 AT 자체는 만료 시간(1시간)까지 유효 — 즉시 무효화 필요하면 RT만 revoke해도 다음 갱신 시 거부됨. 이게 의도된 동작 ([../CLAUDE.md](../CLAUDE.md) 인증 섹션 참고).

### 3. JWT secret 운영 키 정비 ✅
- ✅ 공통 `application.yaml`에서 jwt secret 제거 — fallback이 있으면 prod에 dev 키가 새어나갈 위험이라 의도적으로 비움.
- ✅ `application-local.yaml`에 dev 키 (의미 있는 평문 → Base64). 환경 식별이 쉽고 부담 없이 코드/문서에 등장 가능.
- ✅ `application-prod.yaml`에 `openssl rand -base64 64`로 생성한 512bit 랜덤 키. **이 키는 git 추적되므로 절대 외부 공유/리포 공개 금지.** 노출 시 즉시 회전(yaml 교체 후 재부팅 → 기존 AT/RT 일괄 무효화).
- 🟡 키 노출 의심 시 대응: `openssl rand -base64 64`로 새 키 생성 → `application-prod.yaml`의 `tenk.auth.jwt.secret` 교체 → 재부팅. 서명 검증 실패로 기존 AT/RT 즉시 거부됨. 별도 블랙리스트/Redis 필요 없음.

### 4. 챌린지 → 지출(영상 업로드) → 배지 흐름 E2E
- multipart 요청 형식: `request`(application/json) + `video`(video/*) part 2개. Swagger UI에서 직접 시도 가능 (Authorize 버튼에 Bearer 토큰 입력 후).
- 무지출 기록만 4일 연속 → `NO_SPEND` condition_value=3 배지 자동 지급되는지.
- 챌린지 종료 후 `POST /finalize` → `CHALLENGE_SUCCESS` 배지 지급되는지.

### 5. 통합 테스트 작성 (현재 없음)
- 도메인별 `@SpringBootTest` 시나리오 테스트가 0개. 최소한 다음 4개는 빠르게 추가하면 좋음:
  - `ChallengeServiceTest` — 7일 초과/역순 기간 검증, finalize SUCCESS/FAIL 분기
  - `AmountServiceTest` — 지출 시 영상 누락 → `AMOUNT_VIDEO_REQUIRED`, 무지출 시 영상 없어도 통과
  - `BadgeGrantServiceTest` — `consecutiveStreakEndingOn` 경계값 (오늘 미기록·어제까지 연속 케이스 등)
  - `AuthServiceTest` / `JwtTokenProviderTest` — RT 회전, 만료 AT 거부, 카카오 응답 모킹

### 6. 페이지네이션 / 정렬
- `/api/challenges`, `/api/challenges/{id}/amounts`가 전체 목록 반환 중. `Pageable` 도입 시점 결정.

### 7. Google / Naver 로그인 추가 (예정)
- 동일한 패턴: `GoogleTokenVerifier` / `NaverTokenVerifier` + `AuthService`에 분기 + `POST /api/auth/google/login` / `/naver/login` 엔드포인트. **브라우저 redirect 흐름은 사용하지 않음** (모바일 SDK 전제).

### 8. 운영 고려사항 (필요해지면)
- 영상 저장소를 S3/MinIO로 옮기는 경우: `LocalFileStorage`를 인터페이스로 추출 후 구현체 분리.
- 영상 워터마크(날짜·잔액 오버레이) 기능 — 이번 범위 제외했지만 추후 FFmpeg 도입 시 별도 서비스 분리 권장.
- `open-in-view: false`로 인해 컨트롤러에서 lazy 컬렉션 접근 금지. DTO 변환을 서비스 안에서 끝낼 것.
- AT 강제 무효화(블랙리스트)가 필요해지면 Redis 도입 검토 — 현재는 AT 만료 시간(1시간)에 의존.

## 알려진 주의사항 / 함정

- **DDL과 엔티티가 어긋나면 부팅 실패** (`ddl-auto=validate`). 컬럼·인덱스 추가 시 `docs/schema.sql`도 같이 수정 후 DB에 적용해야 함.
- **`BadgeGrantService.consecutiveStreakEndingOn`은 "오늘 기록이 없으면 어제 기준"** 까지만 봐줌. 이틀 이상 비면 streak=0. 의도된 동작.
- **`@CurrentUserId`가 비인증 요청에서는 null**. `SecurityConfig.PERMIT_ALL`에 새 경로 추가하는데 그 경로에서 `@CurrentUserId`를 받으면 NPE. 인증 필요 경로면 PERMIT_ALL에 넣지 말 것.
- **`JwtAuthenticationFilter`에서 토큰 invalid/expired는 401을 직접 응답한다** (Bearer 헤더가 *있을 때만*). 헤더가 아예 없으면 그대로 통과시키고 `AuthenticationEntryPoint`가 401 처리. 보호 자원에서 만료 토큰이 401로 떨어지면 클라이언트는 RT로 refresh를 시도해야 함.
- **AT는 stateless** — 로그아웃해도 AT 만료 시간까지 유효. 즉시 무효화가 필요하면 RT만 revoke해도 보통은 충분 (다음 갱신 시 거부됨).

## 옮겨야 하는 비-git 자산

- 카카오 앱 ID + (필요 시) Client Secret — 둘 다 git에 박는 정책이지만, 새 머신에 카카오 디벨로퍼스 계정 접근이 필요할 수 있음
- DB 비밀번호 (지금은 `application-local.yaml`에 박혀 git 추적 중)
- JWT secret (prod 환경에서 별도 키 사용 예정)
- (선택) MariaDB 데이터 — 새 환경에서 `schema.sql` 다시 적용해도 무방하면 불필요
- (선택) `tenk-backend/uploads/` 디렉토리 — 이번 머신 영상이 필요 없으면 무시
