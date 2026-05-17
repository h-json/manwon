# Handoff — Tenk 백엔드

> 다른 컴퓨터/세션에서 이 작업을 이어받는 사람(또는 미래의 나)을 위한 인계 노트.
> 영구적인 규칙·결정은 [../CLAUDE.md](../CLAUDE.md)에 있고, 이 문서는 **현재 진행 상태와 다음 할 일**만 기록함.

마지막 갱신: 2026-05-17

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

## 남은 일 (우선순위 순)

### 1. Flutter 앱 초기 구성 (tenk_app/)
- ✅ 스캐폴딩 완료: `flutter create --org com.hjson --project-name tenk_app --platforms android,ios .` (Android applicationId/iOS bundle ID 모두 `com.hjson.tenk_app`)
- ✅ 의존성 추가: `kakao_flutter_sdk_user`, `dio`, `flutter_secure_storage`, `camera`
- 남은 일:
  - 카카오 디벨로퍼스에서 **Android 키 해시 + iOS Bundle ID(`com.hjson.tenk_app`)** 등록 (모바일 플랫폼 설정).
  - Android: `tenk_app/android/app/build.gradle`에서 `minSdkVersion` 카카오 SDK 요구사항(21 이상) 확인.
  - iOS: `tenk_app/ios/Runner/Info.plist`에 카카오 SDK URL scheme 등록 (`kakao{APP_KEY}`).
  - AT/RT를 `flutter_secure_storage`에 저장 + 401 시 자동 refresh 인터셉터 (dio Interceptor).
  - 백엔드 base URL: Android 에뮬레이터 `http://10.0.2.2:8080`, iOS 시뮬레이터 `http://localhost:8080`. 환경별 분기는 `--dart-define=API_BASE_URL=...` 권장.
  - 카메라 권한: Android `tenk_app/android/app/src/main/AndroidManifest.xml`, iOS `tenk_app/ios/Runner/Info.plist`에 `NSCameraUsageDescription` 추가.

### 2. 카카오 앱 ID 박고 실제 로그인 흐름 검증
- `application.yaml`의 `tenk.auth.kakao.app-id`를 실제 카카오 앱 ID(숫자)로 교체.
- 부팅 후 모바일에서(또는 카카오 디벨로퍼스 도구로) access token 받아서 `POST /api/auth/kakao/login` → AT/RT 응답 확인.
- `Authorization: Bearer <AT>` 헤더로 `GET /api/users/me` 200 확인.
- `POST /api/auth/refresh`로 RT 회전 확인 (기존 RT가 두 번째 호출에서 401 되는지).
- `POST /api/auth/logout` 후 기존 RT가 401 되는지.

### 3. JWT secret 운영 키로 교체
- `tenk.auth.jwt.secret`은 현재 로컬용 더미 값. prod profile에서 별도 키 사용. **secret 노출 시 모든 발급 토큰 무효화 + 회전 필요**.

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
