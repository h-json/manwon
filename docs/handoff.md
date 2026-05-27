# Handoff — Tenk

> 다른 컴퓨터/세션에서 이 작업을 이어받는 사람(또는 미래의 나)을 위한 인계 노트.
> 영구적인 규칙·결정은 [../CLAUDE.md](../CLAUDE.md)에 있고, 이 문서는 **현재 진행 상태와 다음 할 일**만 기록함.

마지막 갱신: 2026-05-26 (**챌린지 결과 카드 — 풀스크린 화면 + 영상 export 마지막 클립 통합**. 회의 결정 9개 (진입점, 비율, 영상 포함, 모달 충돌, 닉네임, 색 분기, 카테고리, 표시 형태, 카드 정지 시간) 그대로 반영. **신규 도메인** [presentation/challenge/result_card/](../tenk_app/lib/presentation/challenge/result_card/) (`result_card_widget.dart` + `result_card_screen.dart`) + 캡처 헬퍼 [data/export/result_card_capture.dart](../tenk_app/lib/data/export/result_card_capture.dart) + 신규 데이터 [data/user/](../tenk_app/lib/data/user/) (UserApi + UserScope, `/api/users/me` 로 닉네임 fetch). 진입점 2개: ① finalize 직후 자동 풀스크린 push — 기존 `_finalize` 의 배지 모달 큐 끝난 뒤 ② 챌린지 상세의 "결과 카드" 카드 (확정 후). 영상 export 화면 체크박스 (기본 ON) 로 마지막 3초 정지 클립 합성 — [VideoComposer.compose](../tenk_app/lib/data/export/video_composer.dart) `resultCardPngPath` 옵션 + `_normalizeStaticImageClip` 헬퍼 + `_concatWithXfade` 가 가변 duration 지원하게 시그니처 변경 (`durations: List<double>`, 기존 단일 길이 가정 제거). 캡처 패턴 = Overlay off-screen + RepaintBoundary + 배지 자산 precache + 2 frame 대기 → `toImage(pixelRatio)`. 색은 ThemeData 안 쓰고 위젯에 hardcode — 캡처가 컨텍스트 변동 영향 안 받게. 디테일은 아래 "결과 카드 회의록" 참고. **백엔드 변경 0**. flutter analyze 0 issues. **⚠️ 실기기 미검증** — 직전 SafeArea 픽스와 마찬가지로 작업 환경에서 빌드·런을 못 했음. 검증 항목은 아래 "남은 일 §1 실기기 테스트" 에 추가. 다음 우선순위는 업적 시스템 또는 메모 노출.)

이전 갱신: 2026-05-26 (**하단 시스템 바 가림 픽스 — body SafeArea(top:false) 전 화면 일관 적용**. 안드로이드 일부 기기의 제스처 내비/3-버튼 바가 본문 하단을 깔아뭉개던 백로그 항목 처리. 처음엔 사용자가 핀포인트로 짚어준 4 화면만 손댔다가 "전체 일관성이 깨진다" 는 지적으로 전수 통일로 전환. **규칙**: AppBar 가 있는 모든 화면(현재 10 개)의 Scaffold body 를 `SafeArea(top: false, child: ...)` 로 감싸 bottom·side inset 만 처리 — top 은 AppBar 가 알아서. AppBar 없는 화면(login)은 `SafeArea(...)` 전체 방향. 화면별로 SafeArea 가 있는 곳·없는 곳이 섞여 있으면 디바이스 따라 가림이 들쭉날쭉해지므로 패턴을 화면 추가 시점에 동일하게 가져갈 것. **적용 화면**: amount_record / amount_edit / amount_camera / amount_video_preview / challenge_list / challenge_detail / challenge_create / export_screen / export_prefetch / export_compose / export_result. edge-to-edge 전환은 보류 — 작업량 크고 디자인 자유도가 당장 필요하지 않음. **⚠️ 실기기 미검증** — 작업 시점에 실기기 테스트 환경이 없어 빌드·런 확인을 못 했다. 다음 머신/세션에서 11 화면 전수로 안드로이드 실기기(특히 제스처 내비 ON 인 기기 + 3-버튼 내비 기기) 에서 하단 액션 버튼이 시스템 바 위로 노출되는지 확인해야 한다. 자세한 체크리스트는 아래 "남은 일 §1 실기기 테스트" 참고. 다음 우선순위는 백로그 다음 항목 (업적 시스템 / 영상 export 결과 카드 / 메모 노출).)

이전 갱신: 2026-05-26 (**카메라 녹화 시작 효과음 — royalty-free MP3 + 탭 즉시 트리거 분리**. ① 합성음 한계: 1차 1200Hz sine → 2차 종소리 chime → 3차 두 음 ascending ding 까지 시도했지만 셋 다 "합성음 같다" 인상 못 벗음. 결국 royalty-free MP3 다운로드로 갈아탐 ([assets/sounds/record_start.mp3](../tenk_app/assets/sounds/record_start.mp3)). README 의 PowerShell 합성 스니펫은 제거하고 사이트 후보 (freesound/pixabay/mixkit/zapsplat/soundbible) 만 남김. ② 트리거 위치 분리: 기존엔 효과음+햅틱+morph snap 셋 다 `_recording=true` 전환 시점 (= `startVideoRecording` resolve + `_encoderStartLag` 1초 뒤) 이었는데, 사용자 인지 모델로는 "녹화 중에 소리가 났다" 로 어색하게 잡힘 (영상엔 enableAudio:false 라 안 들어가도). 효과음만 탭 즉시로 옮겨 "버튼 인식" 신호로 분리, 햅틱+snap 은 녹화 시작 시점 유지해 "지금부터 녹화" 신호로 역할 분리. 카메라 화면 작업은 여기서 일단락 — 다음 우선순위는 "남은 일 #1 앱 UX 다듬기 백로그")

이전 갱신: 2026-05-25 (**카메라 녹화 시작 UX — transitional morph + audioplayers chime**. ① 애니메이션: 대기 구간을 idle UI 와 recording UI 를 잇는 단방향 morph 로 통일 — 안쪽 빨간 원(56px) → 둥근 사각형(28px) 3구간 piecewise (12% anticipation, 73% main morph, 15% snap = scale 1→1.15→1). 라디오 링·preview 글로우·심박 펄스 시도했다가 제거 (정지 효과로 읽혀 의도 전달 X). ② 사운드: `SystemSound`/`HapticFeedback` 으론 안 들려서 `audioplayers ^6.1.0` + 자체 PowerShell 합성 WAV 로 정착. 함정: `PlayerMode.lowLatency` 는 `setSource` 미지원이라 사전 로드 패턴 쓰려면 기본 MediaPlayer 모드 유지할 것. 1차 1200Hz 순수 sine 은 "기계음" 피드백 받아 종소리 chime (fundamental + 1500/2200Hz 하모닉 + exponential decay + 도입 pitch chirp, 280ms, ~12KB) 으로 교체.)

이전 갱신: 2026-05-25 (**카메라 녹화 시작 UX — preview freeze 제거 + 준비 중 오버레이**. ① UX 마스킹: `_starting` 동안 프리뷰 위 dim + "녹화 준비 중" 오버레이 + 녹화 버튼 안 빨간 점 심박 펄스 (`_pulseController`). 예전 `CircularProgressIndicator` 는 "로딩 중" 으로 읽혀서 교체. ② 원인 제거: `camera_android_camerax 0.7.2` fork — `initializeCamera` 의 `bindToLifecycle` 에서 `imageAnalysis` 자리에 `videoCapture` 를 넣어 eager bind + `stopVideoRecording` 의 unbind 제거. 두 군데 `[tenk fork patch]` 주석. CameraX 의 lazy bind 가 매 녹화 시작마다 capture session 을 재구성해 preview freeze 를 유발하는 원인을 제거. pubspec.yaml `dependency_overrides` 로 vendor 주입. 다음 우선순위: 실기기에서 freeze 가 실제로 사라졌는지 확인 + `_encoderStartLag` 1초가 여전히 필요한지 재측정)

이전 갱신: 2026-05-25 (**배지 획득 풀스크린 축하 모달 도입 (Lottie)**. 챌린지 응답의 신규 배지를 챌린지 상세 화면에서 감지 → 풀스크린 모달로 배지 elasticOut 줌·wobble·글로우 + 햅틱 + Lottie 컨페티 overlay + "🎉 배지 획득!" + label. diff 는 `_knownBadgeIds` (challengeBadgeId 기반) + `_baselineSet` 으로 첫 로드는 baseline 만 채우고 과거 배지는 다시 축하하지 않음. 트리거 지점은 ChallengeDetailScreen 만 — 메인/홈 등 다른 진입점은 추후 BadgeNotifier 로 승격할 때 같이. `confetti.json` 자산은 사용자가 LottieFiles 무료 에셋 받아 넣는 구조, 없으면 컨페티만 조용히 생략. 다음 우선순위: 결과 카드 회의)

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
6. 백엔드 테스트: `cd tenk-backend && ./gradlew.bat test` (총 84개 그린 — 단위 62 + 통합 17 + WebMvc 4 + ContextLoads 1). ⚠️ **테스트 실행 시 로컬 `tenk` DB의 user/challenge/amount/challenge_badge/refresh_token 데이터가 비워진다** (badge 마스터는 유지). Flutter 재로그인으로 복구 가능
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

- ✅ **Flutter 앱**: 카카오 로그인 + 챌린지 CRUD + 지출/무지출 기록 + 2초 영상 녹화·업로드(`camera` ResolutionPreset.medium + enableAudio:false) + 일시 picker + 잔액 반영 + 삭제 + finalize. **에뮬레이터 E2E 통과 (2026-05-19)**. 구조는 `lib/app/`(셸) + `lib/data/`(api/repository) + `lib/presentation/`(화면) 3층. 컨벤션은 [../CLAUDE.md](../CLAUDE.md) "패키지 구조 (Flutter 앱)" + "코딩 컨벤션 — Flutter" 참고.

- ✅ **배지 도메인 모델 재편 — 유저 단위 → 챌린지 단위** (2026-05-21). 한 챌린지 안에서만 의미를 갖도록 재편. 같은 사용자가 챌린지 A 와 B 에서 똑같이 STREAK 7 을 얻으면 `challenge_badge` 행이 두 개. 챌린지 응답(`ChallengeResponse.badges`)에 인라인 노출. 전용 "배지 화면"·진입점·잠금 상태 UI 모두 제거. 유저 단위 누적(=업적)은 별도 시스템으로 추후 추가.
  - 백엔드: `user_badge` → `challenge_badge` (PK 변경, FK 가 user_id → challenge_id), `UserBadge` → [ChallengeBadge](../tenk-backend/src/main/java/com/hjson/tenk/domain/badge/ChallengeBadge.java), [BadgeGrantService](../tenk-backend/src/main/java/com/hjson/tenk/domain/badge/BadgeGrantService.java) 는 `evaluateForChallenge(challengeId)` / `grantChallengeSuccess(challengeId, result)` 로 시그니처 변경. streak 끝나는 기준일 = `min(today, challenge.endDate)`. amount 쿼리도 user 전체 lookback → 챌린지 내부만. `BadgeController` 와 `GET /api/badges/me` 삭제.
  - 챌린지 API: [ChallengeResponse.badges](../tenk-backend/src/main/java/com/hjson/tenk/domain/challenge/dto/ChallengeResponse.java) 인라인 + [AcquiredBadgeResponse](../tenk-backend/src/main/java/com/hjson/tenk/domain/badge/dto/AcquiredBadgeResponse.java). [ChallengeService.toResponse](../tenk-backend/src/main/java/com/hjson/tenk/domain/challenge/ChallengeService.java) 가 badge JOIN FETCH (직전 운영 LazyInit 버그 패턴 재발 방지).
  - Flutter: `lib/data/badge/badge_api.dart` · `lib/presentation/badge/` 삭제, `BadgeScope` 삭제, AppBar 🏆 진입점 제거. [Challenge.badges](../tenk_app/lib/data/challenge/challenge.dart) 필드 + [ChallengeBadgesRow](../tenk_app/lib/presentation/challenge/widgets/challenge_badges.dart) 위젯 신설 — 챌린지 카드(작게 26px, max 5+N) / 상세(36px). 잠금 상태는 카탈로그 자체를 없앴으므로 노출 안 함. `assets/badges/` PNG 9장은 그대로 재활용 (업적 화면 도입 시도 재사용 가능).
  - 테스트: `BadgeControllerIntegrationTest` 삭제. `BadgeGrantServiceTest` · `BadgeEventIntegrationTest` · `BadgeSchedulerIntegrationTest` 모두 challenge_badge 기반으로 재작성. `BadgeEventIntegrationTest` 에 챌린지 격리 케이스 1개 추가 (`otherChallengeRecordsDoNotLeakIntoThisChallenge`).
  - DB 마이그레이션: `mysql -u tenk -p tenk < docs/schema.sql` 1회 적용 필요 (DROP & RECREATE). 기존 `user_badge` 행은 모두 폐기.
- ✅ **카카오 키 박힘**: 네이티브 앱 키 `589078d3c7daa590c71d9a6e77080b18` 3곳 (kakao_config.dart + Android build.gradle + iOS Info.plist), 백엔드 `tenk.auth.kakao.app-id = 1459747`. Android 키해시 `Dt3/ajH81vV0Ex78dS1ACaqelWc=` (이 머신 debug.keystore 기준). 새 머신은 [[reference-kakao-android-keyhash]] 절차로 재등록.

- ✅ **백엔드 단위 테스트 49개 그린** (2026-05-19, Mockito + AssertJ). `./gradlew.bat test` 통과. 6개 파일:
  - [ChallengeTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/challenge/ChallengeTest.java) (10) — 30일/시작일 과거/역순/null, isStarted·isFinished·containsDate 경계
  - [AmountTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/amount/AmountTest.java) (9) — spend invariant, noSpend, update 분기
  - [ChallengeServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/challenge/ChallengeServiceTest.java) (7) — loadOwned, finalize SUCCESS/FAIL/이미확정/미종료
  - [AmountServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/amount/AmountServiceTest.java) (6) — 종료/미시작 거부, 영상 필수, happy path
  - [BadgeGrantServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeGrantServiceTest.java) (8) — STREAK 폴백·끊김, NO_SPEND 끊김, CHALLENGE_SUCCESS 분기
  - [AuthServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/auth/AuthServiceTest.java) (9) — kakaoLogin/refresh/logout 전 분기
  - **결정 1 — invariant 우회**: `LocalDate.now()`가 정적이라 "종료된 챌린지" 상태는 `ReflectionTestUtils.setField(c, "endDate", today.minusDays(1))`로 사후 박음. 도메인 객체는 invariant를 거친 진짜 객체 유지.
  - **결정 2 — Mockito strictness**: Badge/Auth 테스트는 `@MockitoSettings(strictness = LENIENT)` (케이스별 stub 조합 다양). 나머지는 STRICT 유지.

- ✅ **배지 이벤트 propagation 통합 테스트 8개 그린** (2026-05-20). `@SpringBootTest` + 로컬 MariaDB. 2개 파일:
  - [BadgeEventIntegrationTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeEventIntegrationTest.java) (6) — `grantChallengeSuccessDirectCall`(가설 검증), `noSpendThreeDaysGrantsBadge`, `multipleNoSpendOnSameDayCountAsOne`, `spendBreaksNoSpendStreak`, `challengeSuccessGrantsBadge`, `challengeFailDoesNotGrantBadge`. 모두 reflection 으로 startDate/endDate 를 backdate 한 챌린지 위에서 동작 (Challenge.validatePeriod 의 `startDate >= today` 제약을 우회).
  - [BadgeSchedulerIntegrationTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeSchedulerIntegrationTest.java) (2) — `batchFinalizesAndGrantsChallengeSuccess` (배치가 미확정 챌린지 확정 + 배지 지급), `batchBackfillsMissedNoSpendBadge` (이벤트 우회로 박힌 amount 도 배치가 보강).
  - [IntegrationTestBase](../tenk-backend/src/test/java/com/hjson/tenk/support/IntegrationTestBase.java) + [application-test.yaml](../tenk-backend/src/test/resources/application-test.yaml): 로컬 `tenk` 스키마 그대로 사용. `@BeforeEach`에서 비-마스터 테이블 DELETE (badge 마스터는 유지). 트랜잭션 롤백 대신 명시적 정리를 쓰는 이유 = `@TransactionalEventListener(AFTER_COMMIT)` 가 실제 커밋 이후에만 발화하므로 테스트가 `@Transactional` 이면 AFTER_COMMIT 이 안 도는 함정.
  - **🚨 운영 버그 발견·수정**: 통합 테스트 첫 실행에서 `[Badge] granted` 로그는 찍히는데 `user_badge` INSERT 가 전혀 일어나지 않는 현상 발견. 원인은 `@TransactionalEventListener(AFTER_COMMIT)` 콜백 시점에 원본 tx 동기화가 정리 중이라 `BadgeGrantService` 의 단순 `@Transactional(REQUIRED)` 가 새 tx 를 못 열고 쓰기가 사라지는 패턴. 가설 검증으로 [`grantChallengeSuccessDirectCall`](../tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeEventIntegrationTest.java) (이벤트 우회 직접 호출 → 정상 저장) vs `challengeSuccessGrantsBadge` (이벤트 경유 → 미저장) 비교. 수정: [BadgeEventListener](../tenk-backend/src/main/java/com/hjson/tenk/domain/badge/BadgeEventListener.java) 리스너 메서드 자체에 `@Transactional(propagation = REQUIRES_NEW)` 추가.
  - **함정 1 — 챌린지 `validatePeriod`**: 도메인 invariant 가 `startDate >= today` 라서 NO_SPEND 3단계처럼 today-2 ~ today 의 spentDt 가 필요한 시나리오는 API 만으로 재현 불가. `createChallenge(userId, today-2, today+1, ...)` 처럼 invariant 통과 후 reflection 으로 startDate 를 사후에 박는 패턴 사용. BadgeGrantServiceTest 와 동일.
  - **함정 2 — 통합 테스트가 dev DB 데이터를 비움**: 위에 적은 대로 별도 `tenk_test` 스키마를 만들지 않고 `tenk` 스키마를 공유한다. 매 테스트 실행 시 user/challenge/amount/refresh_token 비워짐. Flutter 카카오 재로그인으로 복구. tenk_test 분리는 다음 머신 운영자가 원하면 그때 결정.

- ✅ **챌린지 상세 화면 UX 강화** (2026-05-21). 도메인 변경에 맞춰 화면도 정리.
  - **amount 목록 날짜별 그룹화** ([_buildGroupedAmounts](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart)): 최신 날짜 위, 같은 날 안에서도 시간 역순. 그룹 헤더에 "M월 D일 (요일)" + 그날 합계(지출 합산) 또는 "무지출" 라벨. helper 는 [_formatters.dart](../tenk_app/lib/presentation/challenge/_formatters.dart) 의 `formatDayHeader` / `dateOnly`.
  - **오늘 상태 기반 동적 액션 패널** ([_TodayActionPanel](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart)): 진행 중 챌린지에서 3분기.
    - 오늘 무지출 기록 있음 → 강조 카드만 (지출 버튼도 숨김). 사용자가 마음 바꾸려면 무지출 row 삭제 → 다시 두 버튼.
    - 오늘 지출 기록 있음 → "오늘 N원 지출했어요" 카드 + 지출 버튼만 (무지출은 의미 없음).
    - 오늘 기록 없음 → 기존대로 지출/무지출 두 버튼.
  - **무지출 성취감 카드** ([_NoSpendTodayCard](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart)): 트로피 아이콘 + "오늘은 무지출!" + 누적 일수 + NO_SPEND 사다리(3/7/14/30) 게이지 + "다음 배지까지 X일". 등록할 때마다 게이지가 한 칸씩 차는 시각적 진전. 30일 도달 시 "최고 단계 달성 🎉". 누적 정의는 `amounts.where(noSpend).map(day).toSet().length` 로 백엔드 `BadgeGrantService.daysWithOnlyNoSpend` 와 동일.
  - 카드 ladder `[3, 7, 14, 30]` 는 백엔드 `badge` 마스터의 NO_SPEND condition_value 와 1:1. 변경 시 [docs/schema.sql](schema.sql) 시드와 함께 갱신 (CLAUDE.md "배지 카탈로그 변경" 행 참고).
  - 백엔드 변경 없음 — 데이터는 기존 challenge + amounts 응답으로 충분.

- ✅ **영상 합본 export 구현 완료** (2026-05-23). 챌린지 확정 후 기록 영상을 시간순으로 합쳐 1개 MP4 로 만들어 갤러리 저장·공유까지. 회의 결정 13개 항목 그대로 반영. 실기기에서 합성 → 갤러리 저장 → 재생 골든 패스 검증 통과.
  - **Flutter 신규**: 데이터 레이어 — [video_composer.dart](../tenk_app/lib/data/export/video_composer.dart) (ffmpeg 합성 2-pass 래퍼), [media_api.dart](../tenk_app/lib/data/media/media_api.dart) (영상 다운로드). 화면 — [presentation/challenge/export/](../tenk_app/lib/presentation/challenge/export/) 5개 (export_plan/export_screen/export_prefetch_screen/export_compose_screen/export_result_screen). 진입은 [_ExportEntryCard](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart) (챌린지 확정 후에만 non-null).
  - **Flutter 의존성 +5**: `ffmpeg_kit_flutter_new_video` (LGPL 'video' 변종), `path_provider`, `video_player`, `gal`, `share_plus`. 한글 폰트는 [assets/fonts/Korean.ttf](../tenk_app/assets/fonts/) — `pubspec.yaml` 의 `flutter.assets` 에 `assets/fonts/` 등록. 폰트 자체는 git 추적 X (사용자가 직접 OFL 폰트 다운로드 — [README](../tenk_app/assets/fonts/README.md)).
  - **권한**: Android — `WRITE_EXTERNAL_STORAGE android:maxSdkVersion="29"` (gal 의 API 29 이하 호환). `camera_android_camerax` 가 같은 permission 을 maxSdkVersion=28 로 선언해서 manifest merger 충돌 → `tools:replace="android:maxSdkVersion"` 으로 덮어씀. iOS — `NSPhotoLibraryAddUsageDescription` 추가.
  - **백엔드 보강**: [MediaController](../tenk-backend/src/main/java/com/hjson/tenk/domain/media/MediaController.java) 의 download/meta 가 트랜잭션 밖에서 `mediaFile.getAmount().getChallenge().getUser().getId()` 체이닝을 풀어 `LazyInitializationException` 위험 → [MediaFileRepository.findByIdWithAmountChallengeUser](../tenk-backend/src/main/java/com/hjson/tenk/domain/media/MediaFileRepository.java) JOIN FETCH 쿼리로 회피. 회귀 가드 [MediaFileRepositoryIntegrationTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/media/MediaFileRepositoryIntegrationTest.java) 2개 추가 — **백엔드 총 79개 그린**.
  - **인코더 시행착오 (놓치면 같은 함정 재방문)**: `h264_mediacodec`(hw) → return code 0 인데 빈 컨테이너 silent fail. `libx264`(sw H.264) → GPL 이라 'video' 변종 빌드에 미포함. `libkvazaar`(sw HEVC) → cleanup 단계 native crash (`pthread_mutex_destroy called on a destroyed mutex`). 최종 정착은 ffmpeg 내장 **`mpeg4` (MPEG-4 Part 2, LGPL)**. 자세한 경로는 [video_composer.dart](../tenk_app/lib/data/export/video_composer.dart) `_videoEncoder` 상단 주석 + 본 문서 "함정 — H.264/HEVC sw 인코더 다 막힘".
  - **보류 — 결과 카드**: 회의에서 보류된 "영상 끝 3초 결과 카드" 는 이번 구현에 미포함. 챌린지 확정 화면 자체가 분리될 가능성 때문에 후속 결정으로 미룸.

- ✅ **챌린지 결과 카드 — 풀스크린 + 영상 export 마지막 클립** (2026-05-26). 회의 결정 9개 그대로 반영. 영상 export 와 무관하게 챌린지 확정 후 항상 표시되는 1장 카드 (480x864 9:16). flutter analyze 0 issues. **⚠️ 실기기 미검증** (작업 환경 한계).
  - **신규 도메인**:
    - [presentation/challenge/result_card/result_card_widget.dart](../tenk_app/lib/presentation/challenge/result_card/result_card_widget.dart) — 480x864 고정 사이즈 위젯. 색은 ThemeData 안 쓰고 hardcode (성공 = 노랑 그라데이션 + 보라 accent + 🎉, 실패 = 그레이 + 다크 accent + 💪). 빈 슬롯 fallback (배지 0개 / 무지출 0일 → 라인 통째 생략).
    - [presentation/challenge/result_card/result_card_screen.dart](../tenk_app/lib/presentation/challenge/result_card/result_card_screen.dart) — 풀스크린 라우트. FittedBox 로 480x864 카드를 디바이스 비율에 맞춰 표시 + 갤러리 저장/공유 두 버튼. 닉네임 fetch 는 화면 진입 후 background ([UserScope] 통해 `/api/users/me`), fetch 실패하면 헤더만 "만원 챌린지" 로 폴백. 캡처는 첫 호출 시 PNG 1번 만들어 같은 세션 내 재사용.
    - [data/export/result_card_capture.dart](../tenk_app/lib/data/export/result_card_capture.dart) — Overlay off-screen + RepaintBoundary 패턴. 호출자가 `pixelRatio` 선택 (영상용 1.0 / 갤러리·공유용 2.0). 배지 자산 `precacheImage` + 2 frame 대기 필수 — Image.asset 첫 프레임 placeholder 캡처 회귀 방지.
    - [data/user/user.dart](../tenk_app/lib/data/user/user.dart) + [user_api.dart](../tenk_app/lib/data/user/user_api.dart) — UserResponse 모델 + `GET /api/users/me` 호출. [app/scopes.dart](../tenk_app/lib/app/scopes.dart) `UserScope` 추가 + [main.dart](../tenk_app/lib/main.dart) 의존성 주입. 카카오 SDK 의 `UserApi` 와 이름 충돌해서 `hide UserApi` 추가.
  - **진입점 2개**:
    - **자동**: [ChallengeDetailScreen._finalize](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart) 에서 배지 모달 큐 끝난 뒤 `_openResultCard` 호출 — finalize 콜백 경로에서만 push, 첫 로드 / 재진입에는 자동 push 안 됨. 결정 사유 = 모달 충돌은 "배지 → 결과 카드 순차" 로 페이오프 계단.
    - **상세 진입점**: 확정된 챌린지에서만 노출되는 `_ResultCardEntryCard` ([같은 파일](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart)). 영상 만들기 카드 위에 위치 (1순위가 결과 보기).
  - **영상 export 마지막 클립**:
    - [export_screen.dart](../tenk_app/lib/presentation/challenge/export/export_screen.dart) 헤더 배너 아래에 `_ResultCardToggle` 체크박스 (기본 ON) + `_includeResultCard` state.
    - [export_compose_screen.dart](../tenk_app/lib/presentation/challenge/export/export_compose_screen.dart) 가 합성 시작 직전에 `ResultCardCapture.captureToFile(pixelRatio: 1.0)` 호출 → PNG path 만들고 `VideoComposer.compose` 의 신규 `resultCardPngPath` 옵션으로 전달. 영상 export 의 카드는 닉네임 fetch 안 함 (결과 카드 화면이 닉네임 표시 메인 진입점, compose 시작 지연 회피).
    - [video_composer.dart](../tenk_app/lib/data/export/video_composer.dart) `compose()` 가 `resultCardPngPath: String?` 받음 — `_normalizeStaticImageClip` 헬퍼로 `-loop 1 -t 3.0` 3초 mpeg4 클립 만들고 기존 정규화 출력 뒤에 추가. **`_concatWithXfade` 시그니처 변경** — 단일 `_clipDurationSec` 가정 제거 + `durations: List<double>` 받음. xfade offset 누적이 클립별 가변 duration 으로 계산되도록 변경 (기존 모든-2초 케이스 결과는 동일).
  - **백엔드 변경 0**. 기존 challenge / amounts / users/me 응답으로 모두 충분.

- ✅ **카메라 녹화 시작 UX — preview freeze 제거 + transitional morph + 효과음** (2026-05-25). 안드로이드 실기기에서 녹화 시작 시 ① 프리뷰가 잠깐 정지하고 ② 어떤 시각/청각 시그널도 없어 "버튼이 안 먹힌 건가" 로 읽히던 문제 처리.
  - **프리뷰 freeze 원인 제거**: 업스트림 `camera_android_camerax 0.7.2` 가 VideoCapture UseCase 를 `startVideoCapturing` 시점에 lazy bind 라 Camera2 capture session 이 재구성됨 → preview 일시 정지. [vendor fork](../tenk_app/vendor/camera_patched/camera_android_camerax/) 로 fork 떠서 `initializeCamera` 의 `bindToLifecycle` 에서 `imageAnalysis` 자리에 `videoCapture` 를 넣어 eager bind + `stopVideoRecording` 의 unbind 도 제거. `pubspec.yaml` `dependency_overrides` 로 주입. Tenk 는 image stream 을 안 쓰므로 ImageAnalysis 는 lazy 가 무해. CameraX UseCase 조합 표 기준 P+IC+VC 는 LIMITED 이상에서 지원 (4-way 는 LEVEL_3 한정이라 회피). 자세한 절차·재적용 가이드는 [../CLAUDE.md](../CLAUDE.md) "위치별 책임 — camera 패키지 fork 갱신" 행.
  - **시작 transition 의 UX 원칙 — 단방향 모양 변화**: 대기 구간 애니메이션을 idle UI 와 recording UI 를 잇는 단방향 morph 로 통일. 안쪽 빨간 원(56px) → 둥근 사각형(28px) 3구간 piecewise (12% anticipation = scale 0.95, 73% main morph = easeInOutCubic 로 size·radius lerp, 15% snap = scale 1→1.15→1 sine bump). [_RecordButton._morphShape](../tenk_app/lib/presentation/amount/amount_camera_screen.dart). 라디오 링·preview 빨간 글로우·심박 펄스 시도했다가 제거 — 정지 효과로 읽혀 "지금 뭐가 일어나는지" 가 안 전달됐기 때문. 회귀 금지.
  - **사운드 — `audioplayers` + royalty-free MP3** (2026-05-26 최종): `SystemSound.play(click)` 은 시스템 "터치음" 설정 켜진 경우만 동작 (대부분 꺼져 있음). `HapticFeedback` 은 진동만. 결국 `audioplayers ^6.1.0` 의존성 추가. **합성음 한계 4단계**: ① 1200Hz 순수 sine ("기계음") → ② 종소리 chime (1000+1500+2200Hz 하모닉, 280ms) ("합성음") → ③ 두 음 ascending ding (800→1200Hz, 180ms) ("여전히 합성음") → ④ royalty-free MP3 다운로드 ([assets/sounds/record_start.mp3](../tenk_app/assets/sounds/record_start.mp3), ~1.8KB) 로 최종 정착. PowerShell 합성 스니펫은 README 에서 제거하고 사이트 후보 (freesound/pixabay/mixkit/zapsplat/soundbible) 만 남김. **교훈**: 효과음은 합성으로 "효과음 같다" 까지 끌어올리기 어렵다 — royalty-free 다운로드가 항상 효율적. **함정**: `PlayerMode.lowLatency` 는 `setSource` 미지원이라 사전 로드 패턴 (`setSource → seek+resume`) 안 됨 — 기본 MediaPlayer 모드 유지.
  - **트리거 위치 — 효과음만 탭 즉시로 분리** (2026-05-26): 초기엔 효과음+햅틱+morph snap 셋 다 `_recording=true` 전환 시점 (= `startVideoRecording` resolve + `_encoderStartLag` 1초 뒤) 에 같이 울렸음. 사용자 인지 모델로는 "녹화 중에 소리가 났다" 로 어색하게 잡힘 — 영상엔 `enableAudio:false` 라 실제로는 안 들어가도 멘탈 모델이 그렇게 됨. 효과음만 탭 즉시 (`setState(_starting=true)` 직후) 로 옮겨 **"버튼 인식" 신호**로 분리. 햅틱+snap 은 녹화 시작 시점 유지해 **"지금부터 녹화" 신호**로 역할 분리. [amount_camera_screen.dart](../tenk_app/lib/presentation/amount/amount_camera_screen.dart) `_startRecording` 의 두 시그널 호출 위치 참고. 회귀 금지 — 효과음을 다시 녹화 시작 시점으로 옮기지 말 것.
  - **메모리 갱신**: [reference-camera-package-native-patch](.claude-memory) 메모리는 이전(Java listener wrap) 시도가 빠진 흔적만 있었어서 현재 활성 패치 (Dart eager bind) 기준으로 통째로 다시 씀.

- ✅ **배지 획득 풀스크린 축하 모달 (Lottie)** (2026-05-25). 챌린지 응답의 신규 배지를 챌린지 상세 화면에서 감지해 풀스크린 모달로 축하. 듀오링고 스타일 — 배지 elasticOut 줌(0.2→1.0)·wobble 회전(±3.4°)·primary 색 글로우 + 중간 햅틱 1회 + Lottie 컨페티 overlay + "🎉 배지 획득!" + label. 탭으로 닫고 큐 다음 모달 자동 진입.
  - **Flutter 신규**: [badge_celebration_dialog.dart](../tenk_app/lib/presentation/challenge/widgets/badge_celebration_dialog.dart) — `showBadgeCelebrations(context, badges)` 큐 헬퍼 + `_BadgeCelebrationDialog` 위젯 (배지 여러 개 동시 획득 시 순차 표시. 모달 겹치면 dismiss 가 깨지고 시각적으로도 혼란스러워서). 의존성 +1 (`lottie: ^3.1.2`).
  - **diff 감지**: [ChallengeDetailScreen](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart) 가 `_knownBadgeIds: Set<int>` (challengeBadgeId 기반) + `_baselineSet: bool` 보유. `reload()` 오버라이드로 super 완료 후 `_syncBadgesAndMaybeCelebrate()` 호출 — 첫 로드는 baseline 만 채우고, 이후엔 신규 배지만 acquiredDt 오름차순으로 큐 push. `_finalize` 의 `replaceData` 경로에서도 명시 호출 (mixin reload 우회 경로라 자동 hook 안 걸림).
  - **자산**: [assets/lottie/](../tenk_app/assets/lottie/) 디렉토리 신설 + pubspec `flutter.assets` 등록. `confetti.json` 은 사용자가 [LottieFiles](https://lottiefiles.com/) 무료 에셋 받아 넣는 구조 (라이선스 결정 회피). 없으면 컨페티만 조용히 생략 — `Lottie.asset(errorBuilder:)` 폴백, 배지 줌·바운스는 그대로. 사용 가이드는 [assets/lottie/README.md](../tenk_app/assets/lottie/README.md).
  - **트리거 지점은 ChallengeDetailScreen 만** — 메인/홈 등 다른 진입점은 현재 범위 밖. 알리고 싶으면 global `BadgeNotifier` 로 승격 (Scope 에 추가, AmountApi/ChallengeApi 응답 시 알림). 자세한 정책은 [../CLAUDE.md](../CLAUDE.md) "배지 UI 원칙" 참고.
  - **검증**: 디버그 IconButton 으로 가짜 배지 3개(STREAK 3 / NO_SPEND 7 / CHALLENGE_SUCCESS) 큐 동작 + 애니메이션 확인 후 제거. 실제 diff 경로(NO_SPEND/CHALLENGE_SUCCESS 백엔드 → reload → 모달) E2E 는 SQL 백데이트 필요해서 미수행 — 다음 머신에서 확인해도 됨. CHALLENGE_SUCCESS 가 제일 가벼움: 챌린지 생성 → SQL `UPDATE challenge SET start_date = CURDATE() - INTERVAL 1 DAY, end_date = CURDATE() - INTERVAL 1 DAY WHERE id = ?` → 앱에서 "결과 확정하기" 탭.

- ✅ **촬영 영상 미리보기 + 수정 화면 영상 미리보기 화면** (2026-05-24). "녹화 영상 미리보기" + "촬영 직후 바로 재생" 두 항목 같이 처리. 실기기에서 retake/delete 흐름까지 골든 패스 검증 통과.
  - **카메라 화면 ([AmountCameraScreen](../tenk_app/lib/presentation/amount/amount_camera_screen.dart))**: 녹화 정지 직후 `video_player` 로 영상을 자동 loop 재생. 탭으로 일시정지/재생. 기존 체크 아이콘 + "2초 영상 녹화 완료" 텍스트는 player 초기화 실패 시 폴백으로만 남김 (저장은 가능). dispose 시 player + 임시 파일 모두 정리.
  - **수정 화면 영상 미리보기 화면 신설 ([AmountVideoPreviewScreen](../tenk_app/lib/presentation/amount/amount_video_preview_screen.dart))**: 영상 + "다시 촬영" / "삭제" 두 버튼. `VideoPreviewAction` enum 으로 부모(edit 화면) 에 액션 반환. 실제 카메라 호출·REMOVE 마킹은 부모 책임. UI 는 카메라 화면의 녹화 후 미리보기와 동일한 레이아웃.
  - **[VideoAttachmentSection](../tenk_app/lib/presentation/amount/widgets/video_attachment_section.dart) 재구성**: `expandable` 플래그로 두 모드 분기. `false` (record 화면): 기존 즉시 모드 — 메시지 + 다시 촬영/삭제 한 번에. `true` (edit 화면): collapsed-by-default — 메시지 + "영상 보기" 버튼만, 미리보기·재촬영·삭제는 위 화면이 책임. record 화면 사용자는 카메라 직후 이미 영상을 봤으므로 즉시 모드가 자연스럽고, edit 화면 사용자는 기존 영상을 못 봤으므로 확인 단계가 필요한 점을 반영.
  - **[AmountEditScreen](../tenk_app/lib/presentation/amount/amount_edit_screen.dart) 서버 영상 lazy 다운로드**: "영상 보기" 첫 탭에 `MediaApi.downloadToFile` 로 `{tmp}/tenk_edit_preview/{fileId}.mp4` 저장. 같은 세션 내 재탭은 캐시 재사용, 화면 dispose 시 파일 삭제. 다운로드 전 같은 경로 잔재 선삭제 + 다운로드 직후 `exists` + `size > 0` 검증 — 둘 다 `video_player` init 실패로 이어지는 케이스 (이전 호출의 partial write / 다른 핸들 점유 / 백엔드 빈 응답) 라 캐시 박기 전 즉시 snackbar 로 차단. 미리보기 화면도 player 초기화 실패 시 실제 예외 메시지를 노출해서 진단 가능.
  - **백엔드 변경 없음** — 기존 `GET /api/media/{fileId}` 다운로드 엔드포인트 재사용. 영상 export 의 prefetch 화면과 같은 패턴.

- ✅ **영상 내보내기 회의 완료 + amount.memo 도메인 추가** (2026-05-21). 영상 합본 export 가 이번 범위로 진입. amount 에 메모 필드(VARCHAR 500, NULL 허용) 추가 — 지출/무지출 양쪽 모두 선택 입력. 빈/공백은 엔티티에서 null 로 정규화 (DTO 분기를 깔끔하게). 용도는 영상 export 자막 디폴트 오버라이드.
  - 백엔드: [Amount.java](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/Amount.java) `memo` 필드 + `spend()`/`noSpend()`/`update()` 시그니처에 memo 추가, [AmountCreateRequest](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/dto/AmountCreateRequest.java) `@Size(max=500) memo` + [AmountController](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/AmountController.java) `@Valid`, [AmountResponse](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/dto/AmountResponse.java) memo 노출.
  - DB: amount 테이블에 `memo VARCHAR(500) NULL` 컬럼. **schema.sql 1회 적용 필요** (DROP & RECREATE).
  - Flutter: [Amount](../tenk_app/lib/data/amount/amount.dart) 모델에 `memo` 필드, [AmountApi.record](../tenk_app/lib/data/amount/amount_api.dart) 에 memo 파라미터, [amount_record_screen.dart](../tenk_app/lib/presentation/amount/amount_record_screen.dart) 에 "메모 (선택)" 입력칸(maxLength 500, 3줄, 지출/무지출 별 hint 분기).
  - 회의록은 아래 "영상 내보내기 회의록 (2026-05-21)" 참고. 13개 항목 결정 + 결과 카드 1개 보류.
  - 테스트 +2 ([AmountTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/amount/AmountTest.java) `spend_happy_path_sets_fields` 에 memo 검증 추가, `spend_blank_memo_is_normalized_to_null` · `noSpend_keeps_memo` 신설, `update_*` 케이스에 memo 검증). 시그니처 변경 따라 AmountServiceTest · BadgeGrantServiceTest · BadgeEventIntegrationTest 호출처 일괄 갱신.

- ✅ **무지출/배지 도메인 정합성 개선** (2026-05-21). 모델 모호성 제거 + 누적 정의 정착. 백엔드 테스트 **75 그린** (단위 55 + 통합 15 + WebMvc 4 + 컨텍스트 1).
  - 무지출 제약 강화: 일시 입력 불가(서버 `LocalDateTime.now()` 강제), 하루 1회(서비스 + DB `uk_amount_no_spend_day` 생성 컬럼 UNIQUE), 수정 불가(원래 수정 API 자체 미구현 — 자동 성립), 지출 등록 시 같은 날 무지출 row + 첨부 영상까지 자동 삭제. 사용자 통지는 [AmountRecordResult](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/dto/AmountRecordResult.java)의 `removedNoSpendCount` 로 → Flutter [challenge_detail_screen.dart](../tenk_app/lib/presentation/challenge/challenge_detail_screen.dart) `_openRecord` 에서 SnackBar.
  - NO_SPEND 정의 변경: "연속 일수" → "챌린지 내 누적 일수". 무지출 5일 → 지출 → 무지출 5일이면 총 10일. STREAK 은 "연속" 유지 (꾸준함 vs 절약 총량 — 보상 의미가 달라서).
  - 배지 회수(revoke): [BadgeGrantService.applyLadder](../tenk-backend/src/main/java/com/hjson/tenk/domain/badge/BadgeGrantService.java) 가 grant/revoke 양방향을 단일 패스로 처리. 회수가 필요한 케이스(예: 무지출 자동 삭제로 누적이 줄어든 경우)에서도 별도 호출 없이 `evaluateForChallenge` 재평가만으로 정합. 검증은 [BadgeEventIntegrationTest.noSpendBadgeRevokedWhenSpendAddedSameDay](../tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeEventIntegrationTest.java).
  - 스키마: amount 에 `no_spend_day_key VARCHAR(64) GENERATED ALWAYS AS (CASE WHEN is_no_spend = 1 THEN CONCAT(challenge_id, '-', DATE(spent_dt)) ELSE NULL END) VIRTUAL` + `uk_amount_no_spend_day` UNIQUE 인덱스. MariaDB 는 partial index 미지원이라 생성 컬럼이 자연스러움. NULL 허용이라 지출 row 끼리는 충돌 안 함.
  - 이벤트 흐름: 지출 시 무지출 자동 삭제 → `AmountRecordedEvent` 발행 → `BadgeEventListener` 가 `evaluateForChallenge` 호출 → revoke 분기로 NO_SPEND 단계 정정. AFTER_COMMIT + REQUIRES_NEW 패턴은 직전 작업에서 정착된 그대로.
  - DB 마이그레이션: `mysql -u tenk -p tenk < docs/schema.sql` 1회 적용 필요 (DROP & RECREATE). 기존 amount row 는 모두 폐기되므로 Flutter 재로그인 후 새로 기록.
  - 추가 테스트: AmountServiceTest +3 (무지출 spentDt 무시·중복 차단·지출 시 자동 삭제), BadgeGrantServiceTest +3 (NO_SPEND 누적 정의·NO_SPEND revoke·STREAK revoke), BadgeEventIntegrationTest +1 (revoke E2E 시나리오). 기존 통합 케이스도 누적 정의에 맞춰 재작성.

- ✅ **통합 테스트 마무리 — Amount 쿼리 경계 + JWT 필터 WebMvc** (2026-05-20). 백엔드 테스트 총 67개 그린:
  - [AmountRepositoryIntegrationTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/amount/AmountRepositoryIntegrationTest.java) (5) — `findUserAmountsBetween` 의 `[from, toExclusive)` 반열린 구간 검증. from 자정 포함·toExclusive 자정 제외, spentDt 정렬, 유저 필터, 빈 결과, 60일 lookback 패턴까지. `BadgeGrantService.evaluateForUser` 가 의존하는 쿼리라 단위 테스트로는 못 잡는 SQL/JPQL 영역을 메움. `IntegrationTestBase` 패턴 재사용 (다른 통합 테스트와 컨텍스트 공유돼 부팅 비용 0). 직접 native insert 로 amount 박는 이유 = `validateDateInChallenge` invariant + 영상 필수를 우회하기 위해.
  - [JwtAuthenticationFilterWebMvcTest](../tenk-backend/src/test/java/com/hjson/tenk/security/JwtAuthenticationFilterWebMvcTest.java) (4) — Swagger 시나리오 1·2·3 자동화: 헤더 없음 401+`C0003`(SecurityConfig EntryPoint), 정상 AT 200, 만료 AT 401+`AU0002`(필터가 직접 응답), 깨진 토큰 401+`AU0001`. `@WebMvcTest(UserController.class)` 슬라이스 + `@Import(SecurityConfig, JwtAuthenticationFilter, JwtTokenProvider)` + `@EnableConfigurationProperties(AuthProperties)` + `@TestPropertySource` 로 시크릿 주입. DB 없이 가볍게 (1.3초). 만료 토큰 생성은 `JwtTokenProvider` 가 TTL 기반이라 만들 수 없어 같은 시크릿 키로 `Jwts.builder()` 직접 호출, expiration 만 과거로 박는 헬퍼 사용.
  - [TenkApplicationTests](../tenk-backend/src/test/java/com/hjson/tenk/TenkApplicationTests.java) — `@ActiveProfiles("test")` 박아서 IntegrationTestBase 와 프로파일 일관화.
  - **🚧 Spring Boot 4 함정**: `WebMvcTest` 어노테이션 패키지가 이동했다. 기존 `org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest` 는 사라졌고 `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest` 가 정답. `spring-boot-starter-webmvc-test` → `spring-boot-webmvc-test` 모듈 안. (`spring-boot-test-autoconfigure` 자체는 SB4 에서 `json` 슬라이스만 남았다.) IDE 가 "WebMvcTest cannot be resolved" 라고 짖으면 이 import 부터 확인할 것.

---

## 남은 일 (우선순위 순)

> 백엔드 테스트(단위·통합·WebMvc) + 영상 합본 export + 배지 획득 축하 모달 + 카메라 녹화 시작 UX (transitional morph + 효과음 royalty-free MP3 + 탭 즉시 트리거 분리) + 챌린지 결과 카드 (풀스크린 + 영상 마지막 클립 합성) 모두 ✅ 완료. 자세한 건 "완료된 것" 섹션 참고. **카메라 / 결과 카드 도메인 일단락** — 다음은 다른 백로그.

### 1. 앱 UX 다듬기 (백로그)
- **회원가입 시 닉네임 설정 화면 추가** — 현재 `AuthService.kakaoLogin` 은 신규 유저를 카카오 닉네임 그대로 자동 프로비저닝하고 바로 AT/RT 만 돌려준다. 사용자가 본인 닉네임을 직접 정할 수 있게 신규 가입 분기에서 닉네임 설정 화면을 띄울 것. **기본값은 카카오톡 프로필 닉네임으로 prefill** (수정·그대로 둘 수 있음). 구현 방향 후보:
  - (a) 백엔드 응답에 `isNewUser` 플래그 추가 → Flutter 가 SessionGate 직후 해당 플래그 보고 NicknameSetupScreen 으로 분기 → 사용자가 확정하면 기존 user update API (혹은 신규 `POST /api/users/me/nickname`) 호출.
  - (b) 별도 `/api/auth/kakao/signup` 엔드포인트를 만들어 nickname 을 body 로 받음 (카카오 토큰 검증 → 첫 가입이면 닉네임 적용해서 user 생성, 이미 있으면 일반 로그인 분기).
  - 검토 포인트: (a) 가 카카오 SDK 재호출 없이 한 번의 토큰 검증으로 끝나서 가볍다. 단점은 자동 프로비저닝 후 닉네임 수정 전 사용자가 앱을 끄면 카카오 닉네임이 남는 점 — 다음 진입 시 닉네임 화면 다시 띄울지 여부 결정 필요. 회의 후 결정.
  - 동시 영향: User 모델·DTO·schema.sql (이미 nickname 컬럼은 있음) / Flutter `app/session_gate.dart` 분기 + 신규 화면 + auth_repository 갱신.
- **챌린지 이름 필드 추가** — 챌린지 생성 시 사용자 정의 이름(예: "5월 외식 줄이기", "여행 전 비상금 챌린지") 을 설정할 수 있게. 현재는 `targetAmount` + 기간만 있어 목록에서 챌린지끼리 구분이 어렵다. 구현 범위:
  - 백엔드: `Challenge.name VARCHAR(100) NOT NULL` 추가, `ChallengeCreateRequest` `@NotBlank @Size(max=100) name`, `ChallengeResponse` 노출, [docs/schema.sql](schema.sql) 컬럼 추가 (DROP & RECREATE 1회 적용 필요), invariant 테스트 추가.
  - Flutter: [Challenge](../tenk_app/lib/data/challenge/challenge.dart) 모델 + [challenge_api.dart](../tenk_app/lib/data/challenge/challenge_api.dart) request body, [challenge_create_screen.dart](../tenk_app/lib/presentation/challenge/challenge_create_screen.dart) 에 입력 필드(필수), [challenge_list / challenge_detail](../tenk_app/lib/presentation/challenge/) 카드·헤더에 이름 노출 (현재 `targetAmount` 강조 자리 일부를 양보하거나 위에 한 줄 더).
  - 결정 필요: ① 필수 vs 선택 (필수 권장 — 목록 구분 목적이라 빈 이름은 의미 없음) ② 최대 길이 (100 안에서 충분히 길어 보이는지) ③ 기존 챌린지 마이그레이션 (드롭/리크리에이트 정책이라 사실상 무관, 다만 prod 운영 시작 후엔 마이그레이션 필요).
- **업적(achievement) 시스템** — 챌린지 경계를 가로지르는 누적 보상. 새 테이블(예: `user_achievement`) + 별도 컨트롤러/서비스 + 별도 Flutter 화면. 자산은 기존 `assets/badges/` 재활용 가능. 배지와 디자인 언어가 자연스럽게 이어지도록 설계.
- **목록에 메모 노출** — 챌린지 상세의 amount 목록 (`_AmountTile`) 에서 memo 가 있을 때 미리보기(1~2줄 ellipsis) 또는 메모 아이콘 배지. 결정 필요: 본문 노출이 좋은지 아이콘만 노출이 좋은지 (긴 메모가 목록 높이를 흔들 수 있음).
- **실기기 테스트** — `--dart-define=API_BASE_URL=http://192.168.x.x:8080`로 같은 Wi-Fi의 PC IP 주입. 에뮬레이터와 카메라 동작이 미묘하게 다름.
  - **🚧 SafeArea(top:false) 픽스 검증 (2026-05-26 적용, 미검증)** — 직전 작업으로 11 화면 (amount_record / amount_edit / amount_camera / amount_video_preview / challenge_list / challenge_detail / challenge_create / export_screen / export_prefetch / export_compose / export_result) Scaffold body 에 `SafeArea(top: false)` 를 일관 적용했지만 작업 시점에 실기기 환경이 없어 빌드·런 확인을 못 했다. 검증 항목:
    1. 모든 화면에서 하단 액션 버튼/콘텐츠가 시스템 내비게이션 바 위로 잘 노출되는지 (가림 없음).
    2. 제스처 내비 ON 기기 + 3-버튼 내비 기기 양쪽 확인 (inset 값이 다름).
    3. 키보드 떠 있을 때(TextField 포커스) 의도치 않은 점프/잘림 없는지 (특히 amount_record / amount_edit / challenge_create 의 메모 입력 시).
    4. padding 이 비좁아 보이는 화면 있으면 그 화면만 추가 EdgeInsets 조정 (현재는 SafeArea 의 viewPadding 만 들어감).
    5. 가로 방향 inset (제스처 영역) 도 보존되는지 노치/punch-hole 기기에서.
  - **부작용 확인** — `SafeArea(top: false)` 가 ListView 의 마지막 항목과 시스템 바 사이에 visual gap 을 만든다. 챌린지 목록의 카드, amount 목록의 마지막 row 등이 의도된 만큼 떠 보이는지 확인. 너무 떠 있으면 child 의 padding 조정.
  - **🚧 결과 카드 검증 (2026-05-26 적용, 미검증)** — finalize 자동 풀스크린 + 진입점 카드 + 영상 export 마지막 클립 합성 모두 빌드·런 검증 미수행. 검증 항목:
    1. **자동 진입점**: 진행 중 챌린지를 SQL `UPDATE challenge SET start_date = CURDATE() - INTERVAL 1 DAY, end_date = CURDATE() - INTERVAL 1 DAY WHERE id = ?` 로 backdate 후 앱에서 "결과 확정하기" 탭 → 배지 모달(있다면) 뒤 결과 카드 풀스크린이 자동으로 뜨는지. 두 번째 진입 (앱 재진입 시) 엔 자동 push 가 일어나지 않아야 함 — finalize 콜백 경로에서만 push.
    2. **상세 진입점**: 확정된 챌린지 상세에 "결과 카드" 카드가 영상 만들기 카드 위에 노출되는지. 탭 시 풀스크린 진입.
    3. **닉네임 fetch**: 카드 헤더가 "○○님의 만원 챌린지" 로 표시되는지 (카카오 닉네임). 백엔드가 느리거나 실패하면 그냥 "만원 챌린지" 로 폴백 — 화면이 안 깨져야 함.
    4. **갤러리 저장**: 한 번 누른 뒤 "저장됨" 으로 라벨 바뀜 + Tenk 앨범에 PNG 저장 확인. HiDPI 디바이스에서 960x1728 해상도로 저장되는지 (pixel ratio 2.0).
    5. **공유**: PNG 가 share sheet 에 실리는지. 인스타 스토리·카카오톡 등 앱별 다이얼로그 정상 통과.
    6. **영상 export 결과 카드 포함**: export 화면의 체크박스 기본 ON 상태에서 영상 만들기 → 합성 결과 영상 끝에 결과 카드가 3초 정지 화면으로 들어가는지. xfade 0.3초로 자연스럽게 들어와야. 체크 해제 시 결과 카드 없이 영상만 생성.
    7. **빈 슬롯**: 배지 0개 챌린지에서 결과 카드의 배지 row 가 통째 사라지는지 (높이도 안 잡힘). 무지출 0일 챌린지에서 통계 카드의 "무지출" 라인 사라지는지.
    8. **성공/실패 색**: 성공 = 노랑 그라데이션 + 보라 accent + 🎉. 실패 = 그레이 + 다크 accent + 💪. 캡처된 PNG 도 동일한 색감 (ThemeData 영향 안 받음).
  - **부작용 확인**: 영상 export 진행 중 PNG 캡처가 추가됐는데 (compose 시작 시점에 한 번) — 진행 표시 화면이 멈춰 보이지 않는지. compose 단계에서 약간의 추가 지연 (≤ 1초) 발생.

### 2. 페이지네이션 / 정렬
- `/api/challenges`, `/api/challenges/{id}/amounts`가 전체 목록 반환 중. `Pageable` 도입 시점 결정 (지금은 사용자당 챌린지 수가 적어 무방).

### 3. Google / Naver 로그인 추가 (예정)
- 동일 패턴: `GoogleTokenVerifier` / `NaverTokenVerifier` + `AuthService`에 분기 + `POST /api/auth/google/login` / `/naver/login`. **브라우저 redirect 흐름은 사용하지 않음** (모바일 SDK 전제).

### 4. 운영 고려사항 (필요해지면)
- **영상 저장소 S3/MinIO 이전** — `LocalFileStorage`를 인터페이스로 추출 후 구현체 분리.
- **AT 강제 무효화(블랙리스트)** — 필요 시 Redis. 현재는 AT 만료 시간(1시간)에 의존.
- **CI 도입** — 현재 통합 테스트가 로컬 `tenk` 스키마를 비우는 구조라 CI 에서 그대로 못 돈다. 도입 시 Testcontainers + 별도 `tenk_test` 스키마로 갈아탈 것.

---

## 알려진 주의사항 / 함정

### 백엔드
- **DDL과 엔티티가 어긋나면 부팅 실패** (`ddl-auto=validate`). 컬럼·인덱스 추가 시 `docs/schema.sql`도 같이 수정 후 DB에 적용.
- **`BadgeGrantService.consecutiveStreakEndingOn`은 "오늘 기록이 없으면 어제 기준"** 까지만 봐줌. 이틀 이상 비면 streak=0. 의도된 동작.
- **`@CurrentUserId`가 비인증 요청에서는 null**. `SecurityConfig.PERMIT_ALL`에 새 경로 추가하는데 그 경로에서 `@CurrentUserId`를 받으면 NPE. 인증 필요 경로면 PERMIT_ALL에 넣지 말 것.
- **`JwtAuthenticationFilter`에서 토큰 invalid/expired는 401을 직접 응답** (Bearer 헤더가 *있을 때만*). 헤더가 아예 없으면 그대로 통과 + `AuthenticationEntryPoint`가 401 처리.
- **AT는 stateless** — 로그아웃해도 AT 만료 시간까지 유효. 즉시 무효화 필요하면 RT만 revoke하면 다음 갱신 시 거부됨 (Swagger 시나리오 2로 확인됨).
- **JWT secret 노출 시 대응**: `openssl rand -base64 64`로 새 키 생성 → `application-prod.yaml`의 `tenk.auth.jwt.secret` 교체 → 재부팅. 서명 검증 실패로 기존 AT/RT 즉시 거부. 별도 블랙리스트/Redis 필요 없음.
- **`@TransactionalEventListener(AFTER_COMMIT)` 에서 DB 쓰기**: 리스너 메서드 자체에 **`@Transactional(propagation = REQUIRES_NEW)`** 필수. 안 박으면 `[Badge] granted` 로그는 찍히는데 INSERT 가 사라진다 (AFTER_COMMIT 콜백 시점에 원본 tx 동기화가 정리 중이라 단순 REQUIRED 가 새 tx 를 못 연다). [BadgeEventListener](../tenk-backend/src/main/java/com/hjson/tenk/domain/badge/BadgeEventListener.java) 참고.
- **통합 테스트가 `tenk` 스키마 데이터를 비움**: [IntegrationTestBase](../tenk-backend/src/test/java/com/hjson/tenk/support/IntegrationTestBase.java) 의 `@BeforeEach` 가 user/challenge/amount/refresh_token 을 DELETE 한다 (badge 마스터 9행은 유지). `./gradlew test` 후 Flutter 카카오 재로그인 필요. tenk_test 스키마 분리는 일부러 안 함 (다음 운영자가 원하면 그때).

### Flutter
- **목록/상세 화면의 비동기 데이터는 `AsyncStateMixin` + `AsyncStateView` 사용**, `FutureBuilder` 금지 ([presentation/common/async_state.dart](../tenk_app/lib/presentation/common/async_state.dart)). 한 화면이 두 종류 이상의 비동기 자원을 다루면 mixin 대신 직접 state.
- **Navigator push/pop의 generic은 양쪽 모두 명시.** `MaterialPageRoute<T>(builder: ...)`로 T를 박지 않으면 result가 null로 빠지는 경우. push 종료 시점에 무조건 refresh하는 패턴이 안전.
- **에뮬레이터에서 텍스트가 첫 프레임에 안 보이고 화면을 움직이면 나타나면** [[reference-flutter-android-impeller-text-glitch]] — Impeller 텍스트 atlas 버그. `flutter run --no-enable-impeller`로 검증.
- **매니페스트(`AndroidManifest.xml`) 변경은 hot reload로 반영 안 됨.** 콜드 부팅(`q` → `flutter run`) 또는 hot restart(`R`).
- **카카오 키해시는 머신마다 다름.** 새 머신 [[reference-kakao-android-keyhash]] 절차로 재등록.
- **실기기에서 백엔드 도달 불가**: 기본 base URL 인 `10.0.2.2` 는 에뮬레이터 전용 호스트 루프백. 같은 Wi-Fi 의 실기기에서 PC 백엔드를 호출하려면 PC LAN IP 로 바꿔야 한다. 증상은 "카카오 동의 화면까지는 뜨는데 그 뒤 로그인이 안 됨" — 카카오 SDK 는 인터넷에 닿지만 백엔드 교환 콜이 끊긴다. 현재 머신 IP 와 셋업은 아래 "PC LAN IP" 참고.
- **Android `res/xml/*.xml` 주석에 이중 하이픈 금지**: `<!-- ... -->` 안에 `--` 두 글자가 들어가면 `mergeDebugResources` 가 `ParseError ... 주석에서는 "--" 문자열이 허용되지 않습니다` 로 빌드 실패. XML 1.0 §2.5 strict 적용이라 `--dart-define`, `--flag` 같은 CLI 옵션을 주석에 인용할 때 자주 걸린다. AndroidManifest.xml / network_security_config.xml / 그 외 `app/src/main/res/**.xml` 모두 동일. 해결은 단순히 하이픈을 빼거나 문구를 바꾸면 됨.

---

## 옮겨야 하는 비-git 자산

- **카카오 디벨로퍼스 계정 접근** — 새 머신에서 debug.keystore가 달라 새 키해시 등록 필요. 카카오 앱 ID 자체는 yaml에 박혀 git 추적되지만 콘솔에서 키해시 추가는 사람 작업.
- DB 비밀번호 (지금은 `application-local.yaml`에 박혀 git 추적 중)
- prod JWT secret (현재 `application-prod.yaml`에 박혀 있으나 실제 prod 배포 전 별도 키로 교체 필요)
- (선택) MariaDB 데이터 — 새 환경에서 `schema.sql` 다시 적용해도 무방하면 불필요
- (선택) `tenk-backend/uploads/` 디렉토리 — 이번 머신 영상이 필요 없으면 무시
- (참고) `~/.android/debug.keystore`는 머신별로 다른 게 정상 — Android Studio가 새로 만들어줌. 새 키스토어 → 새 키해시 → 카카오 디벨로퍼스에 추가 등록.

---

## PC LAN IP (실기기 테스트용)

현재 머신·현재 네트워크 기준 **`192.168.0.7`**. 두 곳에 같은 값이 박혀 있다 — IP 가 바뀌면 둘 다 갱신:
1. [.vscode/launch.json](../.vscode/launch.json) 의 `tenk_app (device)` 구성 `toolArgs` 안의 `--dart-define=API_BASE_URL=http://.../...`
2. [tenk_app/android/app/src/main/res/xml/network_security_config.xml](../tenk_app/android/app/src/main/res/xml/network_security_config.xml) 의 마지막 `<domain>`
3. 두 곳 바꾼 뒤 폰 브라우저로 `http://<IP>:8080/swagger-ui.html` 이 뜨는지 확인 (안 뜨면 PC Windows 방화벽 → inbound TCP 8080 허용)

IP 확인: PowerShell `ipconfig` → "이더넷 어댑터 Wi-Fi" 의 IPv4 주소. 공유기 DHCP lease 가 갱신되면 바뀔 수 있으니 잘 안 되면 가장 먼저 의심할 것.

---

## 기록 수정/촬영 분리 회의록 (2026-05-23)

> "지출은 영상 필수 / 카메라가 기록 화면에 인라인 / 등록 후 수정 불가" 세 가지를 한 번에 정리한 회의. 회의록 형식이 아니라 사용자 지시 → 명확화 질의 1회 → 합의된 결정의 요약.

### 사용자 요구 (원문 요약)
1. 영상 첨부는 지출/무지출 양쪽 모두 **선택**.
2. 영상 촬영은 기록 화면 안이 아니라 **전용 카메라 화면**.
3. 기록 카드 탭 → **수정 화면** 진입. 내용 + 영상 모두 수정 (영상은 추가/교체/삭제).

### 결정 사항

| # | 항목 | 결정 |
|---|---|---|
| 1 | 지출 영상 | 필수 → **선택**. 백엔드 `AMOUNT_VIDEO_REQUIRED` 에러코드 자체 삭제. `LocalFileStorage.store()` 의 null 가드는 호출자 책임으로 옮기고 들어오면 `INVALID_INPUT` (프로그래머 오류). |
| 2 | 촬영 화면 분리 | 신규 [AmountCameraScreen](../tenk_app/lib/presentation/amount/amount_camera_screen.dart). `Navigator.pop<String>(path)` 로 결과 반환. 사용 안 한 임시 파일은 본인이 정리 (호출자 책임 X). |
| 3 | 영상 첨부 UI 공용 | 신규 [VideoAttachmentSection](../tenk_app/lib/presentation/amount/widgets/video_attachment_section.dart). "없음 → 촬영하기 / 있음 → 다시 촬영 + 삭제" 두 상태만. record + edit 화면 공용. |
| 4 | 수정 화면 진입 | 기록 카드 탭. 기존 카드의 X 삭제 버튼은 **제거** — 삭제는 수정 화면 안의 별도 버튼에서만. |
| 5 | 지출 일시 수정 범위 | **시간만**, 날짜 고정. 백엔드 DTO 는 `LocalTime` 만 받고 기존 spentDt 의 LocalDate 와 결합. 날짜를 바꾸고 싶으면 삭제 후 재등록. (사용자 지시) |
| 6 | 무지출 일시 수정 | 불가. 서버 now() 강제 그대로. 수정 화면에 일시 섹션 자체 숨김. |
| 7 | 영상 액션 표현 | `videoAction: KEEP / REMOVE / REPLACE` enum. REPLACE 면 video part 필수. backend enum + Flutter enum 1:1 매칭. |
| 8 | 배지 재평가 | **안 한다**. 수정에서는 날짜·noSpend 여부가 안 바뀌므로 STREAK/NO_SPEND 가 변할 수 없음. 영상만 바꿔도 마찬가지. |
| 9 | 종료/시작 전 챌린지 | 수정도 record 와 동일하게 `CHALLENGE_ALREADY_FINISHED` / `CHALLENGE_NOT_STARTED` 로 막음. |
| 10 | 응답 형태 | record 는 기존 `AmountRecordResult` 유지, update 는 갱신된 `AmountResponse` 단건. |

### 동기 사유 (왜 이번에 바꾸나)
- **영상 필수 강제는 마찰** — 2초 영상 자체가 부담스러운 사용자가 있어 진입을 가로막고 있었음. export 는 "있는 영상만 합친다" 정책이라 누락이 생겨도 파이프라인은 영향 없음.
- **카메라 인라인은 폼을 무겁게** — 카메라 초기화 실패가 폼 입력 자체를 막는 케이스가 있었음. 단계 분리로 폼 / 촬영을 독립화.
- **수정 불가의 비용 > 구현 비용** — 이미 `Amount.update()` 가 있었고 엔드포인트만 없는 상태였음. 영상 핸들링까지 합쳐도 PUT 하나로 끝남.

### 백엔드 변경 요약
- DTO: 신규 [AmountUpdateRequest](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/dto/AmountUpdateRequest.java) + `VideoAction` enum.
- 엔드포인트: `PUT /api/challenges/{cid}/amounts/{aid}` (multipart, [AmountController.update](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/AmountController.java)).
- 서비스: [AmountService.update](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/AmountService.java) — 소유권/상태 검증 + spentDt 시간 결합 + `applyVideoAction(KEEP/REMOVE/REPLACE)`.
- 엔티티: [Amount.update](../tenk-backend/src/main/java/com/hjson/tenk/domain/amount/Amount.java) 시그니처에 `LocalDateTime spentDt` 추가 (지출만 검증·반영, 무지출은 무시).
- 테스트: `AmountTest` 의 4-arg `update` 호출을 5-arg 로 갱신 + 일시 변경/범위 회귀 2개. `AmountServiceTest` 의 "영상 필수" 케이스 2개 뒤집기 + `update_*` 6개 추가.

### 프론트 변경 요약
- 데이터: [VideoAction enum](../tenk_app/lib/data/amount/amount.dart) + [AmountApi.update](../tenk_app/lib/data/amount/amount_api.dart) (`PUT` multipart).
- 화면: [AmountCameraScreen](../tenk_app/lib/presentation/amount/amount_camera_screen.dart) 신설, [AmountEditScreen](../tenk_app/lib/presentation/amount/amount_edit_screen.dart) 신설, [AmountRecordScreen](../tenk_app/lib/presentation/amount/amount_record_screen.dart) 의 카메라 인라인 제거.
- 공용 위젯: [VideoAttachmentSection](../tenk_app/lib/presentation/amount/widgets/video_attachment_section.dart) (record + edit 공유).
- 챌린지 상세: `_AmountTile` 의 X 삭제 IconButton 제거 + `ListTile.onTap` 으로 수정 진입. `_buildGroupedAmounts` 시그니처에서 `busy` 인자 삭제, `onDelete` → `onEdit` 로 변경.

### Verification 메모
- 백엔드: `./gradlew.bat test --rerun-tasks` 통과.
- Flutter: `flutter analyze` 통과 — 추가 lint 0건.
- E2E: 에뮬레이터에서 영상 없이 지출 기록·수정·삭제·영상 추가/교체/삭제 모두 동작 확인 (2026-05-23). **주의**: 카메라 인라인 제거 + 필드 삭제는 구조적 변경이라 Flutter **hot reload 로는 안 들어감 — hot restart (`R`) 또는 풀 재실행 필수**. 카메라 프리뷰가 폼 안에 보이면 구코드 동작 중이므로 재시작 필요.

### 알려진 갭
- **PUT 엔드포인트 통합 테스트 없음** — 현재 [AmountServiceTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/amount/AmountServiceTest.java) 가 Mockito 단위 테스트라 multipart 파싱·`@Valid`·시큐리티 필터를 거치지 않는다. `AmountController.record/delete` 도 통합 테스트가 없어 컨벤션과는 일관이지만, multipart wiring 회귀를 잡을 가드가 없는 건 사실. 다음에 amount 컨트롤러 만질 일 있으면 [BadgeEventIntegrationTest](../tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeEventIntegrationTest.java) 패턴으로 `AmountControllerIntegrationTest` 추가하는 게 좋음.

---

## 결과 카드 회의록 (2026-05-26)

> 영상 내보내기와는 무관하게 챌린지 확정 후 결과를 1장 카드로 보여주는 기능. 영상 export 와는 별개 도메인이지만 마지막 클립으로 합성하는 옵션도 같이 결정.

### 사용자 요구사항 (원문 요약)
- 챌린지 종료 후 그 챌린지에 대한 결과 카드. 이미지로 저장하기, 내보내기.
- 영상 내보내기 했을 때 제일 마지막에도 결과 카드를 포함시킬 수 있게.

### 결정 사항 (9)
1. **진입점 = finalize 직후 자동 + 챌린지 상세 진입점 둘 다**. 확정 순간엔 페이오프 모먼트로 자동 풀스크린 push, 나중에 공유하려고 다시 볼 수 있게 상세 화면에 카드 한 장 추가.
2. **비율 = 세로 9:16 / 480x864**. 영상 export 해상도와 1:1 — 마지막 정지 카드로 그대로 붙일 수 있고 (스케일링 0), 스토리/릴스 공유 동선과 일치.
3. **영상 export 포함 = 체크박스 (기본 ON)**. export 화면에 "결과 카드를 영상 끝에 포함" 토글. 끄고 싶은 사용자만 끔.
4. **모달 충돌 = 배지 모달 → 결과 카드 순차**. 결과 카드 안에 획득 배지 row 가 있지만 배지 모달도 그대로 진행해 페이오프 계단을 만든다. 결과 카드가 페이오프 통합 후보였지만, 챌린지 성과가 헤드라인이고 배지는 후속 보상이라 두 단계로 가는 게 명확.
5. **닉네임 = "○○님의 만원 챌린지" 포함** (카카오 닉네임 fetch). 카드 진입 시점에 한 번 `/api/users/me` 호출. fetch 실패하면 그냥 "만원 챌린지" 로 폴백 — 안 깨짐. 영상 export 의 카드는 fetch 안 함 (compose 시작 지연 회피).
6. **성공/실패 색 = 드라마틱 대비**. 성공 = 따뜻한 노랑 그라데이션 + 보라 accent + 🎉. 실패 = 그레이 그라데이션 + 다크 그레이 accent + 💪. 결과가 증명사진처럼 명확해야.
7. **카테고리 분포 제외**. 9:16 자리 빡빡 + 숫자/배지로 정보감 충분. 통계 카드 = 목표/사용/절약(또는 초과)/무지출 4개 라인만.
8. **표시 형태 = 풀스크린 라우트** (모달 X). 480x864 비율을 화면에 띄우면 거의 꽉 차 모달로 띄울 이유가 없음. 영상 export 결과 화면 ([export_result_screen.dart](../tenk_app/lib/presentation/challenge/export/export_result_screen.dart)) 의 갤러리 저장/공유 두 버튼 패턴 그대로 차용.
9. **영상 마지막 카드 정지 시간 = 3초**. 영상 클립 2초 + xfade 0.3초 흐름에 이어서 수자/배지/닉네임 읽을 시간 확보. 2.5초는 짧고 4초는 임팩트로 끝나야 하는 마지막을 늘어뜨림.

### 보류·미반영
- **닉네임 옵션화** — 카드에 닉네임 노출을 설정에서 끄는 토글은 안 둠 (설정 화면 자체가 아직 없음 — 회원가입 시 닉네임 설정 화면 백로그 작업 시 같이 검토).
- **결과 카드 자체 캐싱** — 같은 챌린지 결과 카드를 PNG 로 백엔드/디스크에 영구 저장은 안 함. 매번 challenge + amounts 응답으로 동적 생성 (가벼움).

### 함정·교훈
- **색은 ThemeData 안 쓰고 hardcode**. RepaintBoundary 캡처 시 ThemeData 가 영향 안 받게. 위젯 안에서 모든 색을 const Color 로 박아둠. 회귀 금지.
- **배지 자산 precache 필수**. Image.asset 의 첫 프레임이 placeholder 라 캡처에 비어 들어갈 수 있음. ResultCardCapture 가 호출 전 challenge.badges 전체를 precacheImage 로 미리 캐시.
- **off-screen Overlay + RepaintBoundary 패턴**. 위치는 안 보여도 layout/paint 가 정상 수행되고 RepaintBoundary 가 layer 를 그대로 캡처. Off-screen 좌표는 `-2*width` 로 충분히 멀게.
- **`_concatWithXfade` 가 단일 clipLen 가정**이었던 부분 — 마지막 3초 카드 추가로 가변 duration 으로 변경했음. 다른 가변 클립이 들어와도 그대로 동작. 회귀 시 단일 길이 가정 코드로 돌아가지 말 것.

---

## 영상 내보내기 회의록 (2026-05-21)

> CLAUDE.md "영상 내보내기는 이번 범위에서 제외" 결정을 뒤집은 회의. 챌린지 확정 후 기록 영상들을 시간순으로 합쳐 하나의 MP4 로 만드는 기능을 이번 범위로 편입.

### 사용자 요구사항 (사전 정의)
1. 챌린지 내 모든 기록 목록에 선택 박스. 기본값 전체 선택. 해제하면 그 기록의 영상은 합본 제외.
2. 각 기록에 코멘트 작성 가능 — 영상 중간에 텍스트로 자막 표시. 메모(`amount.memo`)가 있으면 그것이 디폴트.
3. 영상 상단에 대시보드 — 일시 + 잔여금액(목표 - 사용금액). 기록 영상마다 갱신.

### 결정 사항 (13)

| # | 항목 | 결정 |
|---|---|---|
| 1 | 처리 위치 | 클라이언트 (Flutter, `ffmpeg_kit_flutter`). 서버 부담 0, 앱 크기 +30~50MB 감수. |
| 2 | 노출 시점 | 챌린지 확정 후에만 (SUCCESS/FAIL 결정 후) |
| 3 | 선택 화면 row | 축소형 리스트 (체크박스 + 날짜 + 내용 + 금액). 영상 썸네일 없음 — 텍스트만 보고 판단. 코멘트 편집은 row 탭 → 모달 |
| 4 | 기록별 자막 디폴트 | `memo` 있으면 memo, 없으면 지출="내용 금액원" / 무지출="무지출". 사용자가 편집 가능 |
| 5 | 자막 영상 안 표시 | 클립 내내 하단 고정 자막. **구현은 Flutter TextPainter PNG + ffmpeg overlay** (drawtext 폐기, 위 "함정 — drawtext 한글 회귀" 참고) |
| 6 | 상단 대시보드 | `Day N · 잔여 X,XXX원` 포맷 (절대 날짜 대신 상대 진행도 — 스토리라인 느낌) |
| 7 | 잔여금 갱신 | 클립 시작=직전 잔여, 끝=차감 후 잔여로 카운트다운 |
| 8 | 무지출 + 영상 없음 | 2초 텍스트 카드 삽입 (검정 배경 + "무지출 ✓" + 코멘트) |
| 9 | 클립 간 트랜지션 / BGM | 0.3초 cross-fade + 무음 (ffmpeg xfade) |
| 10 | 출력 해상도 | 세로 480x864 통일 (모바일 카메라가 세로 녹화이므로 가로 출력이면 좌우 검은 패딩). 입력 원본은 ResolutionPreset.medium 이라 디바이스마다 다름 — 클립별 스케일 필요 |
| 11 | 합성 진행 UX | 전체화면 진행률 + 캔슬 버튼 (백그라운드 처리 X) |
| 12 | 원본 영상 누락 시 | 1개라도 실패하면 전체 중단 + 재시도 버튼. 부분 합본 안 만듦 |
| 13 | 결과 캐싱 | 안 함 — 매번 새로 합성. 같은 입력으로 다시 들어가도 ffmpeg 재실행 |
| - | 완료 후 동작 | 미리보기(`video_player`) + 갤러리 저장(`gal`) + OS 공유 시트(`share_plus`) 셋 다 노출 |
| - | 기존 `/export` JSON | 유지 (통계·외부 연동용으로 남김) |

### 보류 — 결과 카드 (영상 마지막 3초)

영상 끝에 "성공! 8,200/10,000원" 같은 결과 카드를 붙일지 vs 챌린지 확정 시 별도 결과 화면으로 보여줄지 미정.
챌린지 확정 화면 자체가 별도 의사결정 항목으로 분리될 가능성이 있어 영상 내보내기 구현 도중 함께 정리.

### 구현 시 주의사항

- **백엔드 추가 작업 거의 없음** — 영상 다운로드 엔드포인트가 이미 있으면 그대로. 없으면 인증된 사용자가 자신의 amount 영상을 받을 수 있는 엔드포인트 1개 (현재 [MediaController](../tenk-backend/src/main/java/com/hjson/tenk/domain/media/MediaController.java) 확인 필요).
- **패키지/인코더 선택**: `ffmpeg_kit_flutter_new_video` (LGPL 'video' 변종) 사용 중. sw 인코더는 최종적으로 ffmpeg 내장 **`mpeg4` (MPEG-4 Part 2, LGPL)** 채택. 회의 결정 #1 의 "h264" 표현은 H.264 고집이 아니라 "표준 동영상 코덱" 의미였고 MP4 컨테이너에 MPEG-4 Part 2 도 어디서나 재생 가능하니 무방.
- **함정 — H.264/HEVC sw 인코더 다 막힘**: 후보를 다 돌려본 결과 ffmpeg_kit_flutter_new_video 환경에선 mpeg4 외 선택지가 없다. 다음은 모두 실격 — 같은 함정에 다시 들어가지 말 것:
  - `h264_mediacodec` (hw): lavfi `color` 소스/짧은(2초) 클립 인코딩 시 return code 0 인데 duration N/A + 스트림 없는 빈 컨테이너를 뱉는다. 정규화는 통과한 척 → concat 에서 `[N:v] matches no streams` 로 죽음. 디바이스/펌웨어 의존이라 재현이 일정치 않음.
  - `libx264` (sw H.264): GPL — 현재 'video' 변종 빌드에 미포함, 라이센스 이슈로 채택 X.
  - `libkvazaar` (sw HEVC): 빌드엔 있지만 native crash. ffmpeg `exit_program` → `of_close` → `avcodec_free_context` → `pthread_mutex_destroy` 에서 `FORTIFY: called on a destroyed mutex` SIGABRT. kvazaar 자체 스레드풀과 ffmpeg cleanup 의 더블 프리. 패키지 버그라 사용자 코드 우회 불가.
- **함정 — drawtext 한글 회귀 (ffmpeg 8.0)**: `ffmpeg_kit_flutter_new_video` 2.0.0 은 ffmpeg n8.0 (HarfBuzz 통합 drawtext) 을 쓰는데 multi-codepoint 한글 입력에서 **첫 글리프만 그리고 뒤를 silent drop** 한다. "무지출" → "무", "도시락 챙겼다" → "도", "Day 1 · 잔여 8,000원" → "D" 패턴. 다음 모두 무효였음 — drawtext 로 회귀 X:
  - `text='무지출'` 인라인, `textfile='...'` + `expansion=none`: 둘 다 같은 출력. textfile 내용은 hex dump 로 9바이트 (eb ac b4 ec a7 80 ec b6 9c) 전부 정확히 박혀있는데도 첫 글자만 렌더.
  - `text_shaping=0` 으로 HarfBuzz shaping path 우회 시도: 옵션은 수락되는데 출력 동일. ffmpeg 8.0 drawtext 가 옵션을 받기만 하고 실제로는 새 shaping path 만 쓰는 것으로 추정.
  - 폰트 교체 (Tmoney RoundWind → Pretendard): cmap 으로 한글 11172자 다 커버하는 폰트로 바꿔도 동일. 폰트 글리프 문제 아님.
  - `-loglevel verbose` 에서도 drawtext 가 어떤 경고도 안 뱉음 — 디버그 단서 0.
  - **해결**: drawtext 완전 폐기하고 Flutter `TextPainter` 로 PNG 그려 ffmpeg `overlay` 필터로 합성. Flutter/Skia 가 Android 시스템 폰트 (Noto Sans CJK) 폴백으로 한글 렌더 → ffmpeg 는 그냥 픽셀만 합성하니까 텍스트 렌더링 경로 자체를 차단. 구현은 [video_composer.dart](../tenk_app/lib/data/export/video_composer.dart) `_renderTextOverlayPng` / `_drawTextBlock`.
- **앱 크기**: `ffmpeg_kit_flutter_new_video` 빌드는 +30~50MB. 더 줄이고 싶으면 `_min` 계열도 mpeg4 는 들어있으므로 시도 가능.
- **메모리/배터리**: 30일치(최대 ~60개 클립 × 2초) 합성은 저사양 폰에서 수십 초 걸릴 수 있음. 캔슬 가능해야 함. ffmpeg_kit 의 `Session.cancel()` 활용.
- **자막 렌더**: ffmpeg drawtext 가 한글에서 막혀서 (위 함정) **Flutter TextPainter PNG + ffmpeg overlay** 로 갈아탐. 시스템 폰트 폴백을 쓰니까 별도 폰트 자산 불필요. 자막 폰트를 명시 지정하고 싶으면 [tenk_app/assets/fonts/Korean.ttf](../tenk_app/assets/fonts/) 를 pubspec.yaml `flutter.fonts` 에 family 로 등록 + `_drawTextBlock` 의 TextStyle 에 fontFamily 박기.
- **잔여금 카운트다운**: 한 클립(2초)에서 시작값→끝값으로 보간된 텍스트를 매 프레임 그리려면 drawtext 의 `t` 변수(현재 재생시간)와 expression 활용. 또는 클립 길이를 짧은 세그먼트로 쪼개고 각 세그먼트마다 다른 텍스트 — 후자가 단순.
- **음성 트랙 없음**: 원본 녹화가 `enableAudio:false` 라 입력에 오디오 트랙이 없을 수도 — ffmpeg 명령에 `-an` 명시 또는 무음 트랙 강제 생성으로 출력 일관성 확보.
