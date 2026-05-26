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
  - 영상 녹화: Flutter `camera` 패키지의 **`ResolutionPreset.medium` + 2초 타이머**로 처음부터 가볍게·짧게 촬영. ffmpeg 등 후처리 트랜스코딩은 사용하지 않음. export 파이프라인이 480x864 로 정규화하므로 medium 이상은 의미 없음 (파일만 커짐).
- **현재 단계**: 백엔드 REST API 골격 1차 구현 완료. 통합테스트는 미수행. Flutter 앱은 카카오 로그인 + 챌린지 CRUD + 지출/무지출 기록 + 영상 녹화·업로드 + 배지 화면 + **영상 합본 export(클라이언트 ffmpeg 합성)** 까지 완료.

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
| 테스트(백엔드) | JUnit5 + Mockito + AssertJ. 총 84개: 단위 62 + `@SpringBootTest` 통합 17 (배지 이벤트 8 + 배치 2 + Amount 쿼리 경계 5 + Media JOIN FETCH 2) + `@WebMvcTest` 인증 필터 슬라이스 4 + 컨텍스트 로드 1. `@SpringBootTest` 통합은 **로컬 MariaDB의 `tenk` 스키마를 그대로 사용**하므로 매 테스트 실행 시 user/challenge/amount 등 dev 데이터가 함께 비워진다 (Flutter 재로그인으로 복구). 패턴은 [IntegrationTestBase](tenk-backend/src/test/java/com/hjson/tenk/support/IntegrationTestBase.java) 참고. WebMvc 슬라이스는 DB 없이 가볍게 돈다 ([JwtAuthenticationFilterWebMvcTest](tenk-backend/src/test/java/com/hjson/tenk/security/JwtAuthenticationFilterWebMvcTest.java)) |

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
- 짧은 2초 영상은 **클라이언트가 처음부터 짧게·가볍게 녹화**하는 방식 (사후 변환·트랜스코딩 아님). Flutter 기준 `camera` 패키지의 `ResolutionPreset.medium` + 2초 타이머로 처리. 백엔드는 업로드받은 파일을 그대로 저장. export 가 480x864 로 정규화하므로 medium 위로 올릴 이유 없음 (파일만 커짐).
- **영상은 지출/무지출 양쪽 모두 선택**. 백엔드는 영상 part 가 없거나 빈 multipart 면 그대로 통과 (`AmountService.record`/`update`). 영상이 첨부된 경우에만 `MediaFile` 행을 만든다.
- **촬영 화면은 별도** ([AmountCameraScreen](tenk_app/lib/presentation/amount/amount_camera_screen.dart)). 기록 화면(record/edit)은 [VideoAttachmentSection](tenk_app/lib/presentation/amount/widgets/video_attachment_section.dart) 으로 영상 첨부 상태만 보여주고, 실제 카메라 프리뷰·녹화는 카메라 화면에서만 한다. 사유: 카메라 초기화가 실패해도 폼 입력은 진행 가능해야 하고, 화면 한 곳에 너무 많은 것을 띄우지 않기 위해.
- **카메라 컨트롤**: 플래시(`FlashMode.torch` — 영상이라 지속 점등, `auto`/`always` 는 정지 사진용이라 무의미) / 셀카 전환 / 핀치 줌 / 탭 초점 모두 **녹화 시작 전에만 조정 가능, 녹화 중엔 전부 잠금** (탭 초점 포함). 사유: 2초 영상이라 녹화 중 조작이 결과에 노이즈만 됨 — 시작 전 셋업하고 그대로 찍는 흐름이 깔끔. 핀치 줌은 1손가락 팬이 탭 초점과 충돌하므로 `details.pointerCount >= 2` 일 때만 적용. 플래시 버튼은 후면 카메라일 때만 노출 (전면은 보통 플래시 미지원). 카메라 전환 시 `_flashMode` 는 off 로 reset.
- **줌 preset 버튼 (iOS 카메라 스타일)**: 프리뷰 하단 중앙에 배율 preset row (1x 기본, 디바이스가 ultra-wide 지원하면 minZoom 을 앞에, maxZoom≥2 면 2x, maxZoom≥5 면 5x). 사유: 핀치 줌만 있으면 발견성이 낮아 사용자가 줌 기능이 있는지도 모름. preset 버튼은 익숙한 패턴이라 즉시 인지됨. 현재 zoom 과 ±0.15x 이내인 preset 이 active (흰 원 + 검은 글씨) 강조. 핀치로 preset 사이 값에 멈추면 어느 것도 active 가 아니고 row 위에 작은 chip 으로 실제 값(`1.5x`) 표시. preset 이 1개(=1x) 뿐인 디바이스는 row 자체를 안 그림. 녹화 중·준비 중엔 숨김.
- **프리뷰 종횡비 처리**: `CameraPreview` 를 그냥 Stack 자식으로 두면 `StackFit.expand` 가 내부 AspectRatio 를 무시하고 강제로 늘려서 세로로 길어 보임 (센서 landscape 를 portrait 박스에 stretch). cover-crop 패턴으로 감싸 종횡비 유지 + 박스 채움 — `FittedBox(BoxFit.cover) + SizedBox(width: previewSize.height, height: previewSize.width, child: CameraPreview)` (previewSize 는 센서 기준이라 portrait 표시용으로 width/height swap). 녹화 후 미리보기·서버 영상 미리보기도 같은 패턴 사용. `GestureDetector` 는 `Positioned.fill` 로 분리해 위에 얹어 탭 초점·핀치 줌은 그대로.
- **녹화 시작 흐름 (3단계)**: ① 화면 진입 직후 카메라 init → 곧바로 background 에서 dummy `startVideoRecording`→150ms→`stopVideoRecording`→파일 삭제로 MediaCodec/MediaMuxer 워밍업 (`_warmupEncoder`). 워밍업 중엔 시작 버튼 비활성화 (idle 모습 그대로 disabled). ② 사용자 탭 → `_starting=true` → **탭 즉시 효과음** (`AudioPlayer.resume()` 으로 `assets/sounds/record_start.mp3`, royalty-free) → `_startMorph.forward()` 단방향 0→1 morph 가 즉시 시작 → `await camera.startVideoRecording()` → **추가로 `_encoderStartLag`(1초) 더 대기**. 이 구간 UX = **transitional morph**: idle UI(큰 빨간 원 56px) → recording UI(작은 둥근 사각형 28px) 로 안쪽 모양이 부드럽게 변형 (0~12% anticipation 살짝 작아짐, 12~85% 본 morph, 85~100% snap = scale 1→1.15→1 sine bump). 프리뷰 자체는 vendor fork 패치로 freeze 안 됨. ③ `_recording=true` 전환 직전 듀얼 시그널: `HapticFeedback.heavyImpact()` + morph 의 snap 구간. 효과음은 ② 의 탭 즉시로 분리 — 사유: 효과음을 녹화 시작 시점에 두면 사용자 멘탈 모델로는 "녹화 중에 소리가 났다" 로 읽혀 어색 (enableAudio:false 라 영상 트랙엔 안 들어가지만 인지 모델이 그렇게 잡힘). 탭 즉시 효과음 = "버튼 인식" 신호, 햅틱+snap = "지금부터 녹화 시작" 신호로 역할 분리. 이후 progress arc + 2초 정지 타이머 시작. **사유**: CameraX 의 `startVideoRecording` future 가 실제 인코더 첫 프레임보다 먼저 resolve 되는 경우가 있어, future resolve 직후 바로 2초 타이머를 걸면 실제 캡처가 ~1초로 잘려나가는 회귀가 있었다 (Android 실기기 실측). `_encoderStartLag` 만큼 더 기다린 뒤 게이지를 시작해 캡처 길이를 안정적으로 2초에 맞춤. **트레이드오프**: 사용자가 탭한 순간은 캡처에 포함되지 않음 — 스피너 끝난 뒤 2초가 잡힘. 정확한 탭 순간 캡처가 필요하면 pre-roll + ffmpeg trim 방식이 필요한데 (대화에서 검토 후) 배터리·발열·후처리 비용 때문에 sync wait 로 결정.
- **프리뷰 freeze 제거 (camera 패키지 fork, Android)**: 업스트림은 VideoCapture UseCase 를 `startVideoCapturing` 시점에 lazy bind 하는데 이때 Camera2 capture session 이 재구성되며 프리뷰가 잠깐 freeze 됨. [vendor fork](tenk_app/vendor/camera_patched/camera_android_camerax/lib/src/android_camera_camerax.dart) 의 `initializeCamera` 에서 `ImageAnalysis` 자리에 `VideoCapture` 를 넣어 eager bind, `stopVideoRecording` 의 unbind 도 제거 — 두 군데 `[tenk fork patch]` 주석. Tenk 는 image stream 을 안 쓰므로 ImageAnalysis 는 첫 호출 시 lazy bind 되어도 무해. CameraX UseCase 조합 표 기준 P+IC+VC 는 LIMITED 이상에서 지원 (4-way 는 LEVEL_3 한정이라 회피). `pubspec.yaml` `dependency_overrides` 로 주입. 업스트림 버전 올릴 때 같은 두 지점에 재적용 필요.
- **시작 transition 의 UX 원칙**: 대기 구간엔 oscillating effect (라디오 링·글로우·pulse) 가 아니라 **idle UI 와 recording UI 를 잇는 단방향 모양 변화** 만 둠. 라디오 링·preview 빨간 글로우·심박 펄스는 한 번 시도했다가 제거 — "지금 뭐가 일어나고 있는지" 가 시각적으로 안 전달되고 정지 효과로 읽혔기 때문. 회귀하지 말 것 (`_RecordButton._morphShape` 의 3구간 piecewise + `Curves.easeInOutCubic` 가 정답). 사운드는 `SystemSound`/`HapticFeedback` 으로 우회하다가 실기기에서 안 들려서 `audioplayers` + royalty-free MP3 자산으로 정착.
- **촬영 직후 미리보기** (카메라 화면): 2초 녹화가 끝나면 같은 화면에서 `video_player` 로 영상을 자동 loop 재생 (탭으로 일시정지). "사용" 으로 확정하기 전에 결과 확인. 체크 아이콘 등 placeholder 가 아니라 실제 영상. 초기화 실패 시 체크 아이콘 + "미리보기를 불러올 수 없어요" 로 폴백 (저장 자체는 가능).
- **기존 영상 확인** (수정 화면): 영상이 있을 때 섹션은 collapsed — 메시지 + "영상 보기" 버튼만. 탭하면 [AmountVideoPreviewScreen](tenk_app/lib/presentation/amount/amount_video_preview_screen.dart) 이 새 화면으로 떠 영상 + "다시 촬영" / "삭제" 버튼. 액션은 `VideoPreviewAction` enum 으로 부모에게 반환되고 부모(edit 화면)가 실제 카메라 호출·REMOVE 마킹 처리. 사유: edit 진입 시점에는 사용자가 영상을 못 봤기 때문에 확인 단계가 필요한데, 폼 안 인라인 player 는 화면을 무겁게 만들고 retake/delete 를 영상과 함께 묶어 보여주기에는 별도 화면이 자연스러움. record 화면은 카메라 직후 이미 확인했으므로 기존 즉시 모드 유지 (`expandable: false`).
- **서버 영상 lazy 다운로드** (수정 화면 KEEP 상태): "영상 보기" 첫 탭에 `MediaApi.downloadToFile` 로 `{tmp}/tenk_edit_preview/{fileId}.mp4` 에 저장. 같은 세션에서 재탭 시 캐시 재사용, 화면 dispose 시 파일 삭제. 다운로드 전 같은 경로의 잔재 선삭제 + 다운로드 직후 `exists` + `size > 0` 검증으로 깨진 캐시(이전 호출의 partial write / 다른 핸들 점유) 차단 — 둘 다 `video_player` init 실패로 이어지는 케이스이고 진단이 어려워 사전에 막는 게 싸다.
- 저장소는 로컬 파일 시스템 (`tenk.upload.base-dir`, 기본 `./uploads`). `.gitignore`에 등록됨.
- **녹화 시 음성은 꺼둠** (`CameraController(enableAudio: false)`). 사유: `RECORD_AUDIO` 런타임 권한 프롬프트를 한 단계 줄이기 위해. 추후 음성이 필요해지면 매니페스트 `RECORD_AUDIO`는 이미 선언돼 있으니 코드에서 `enableAudio: true`로만 바꾸면 됨.
- **업로드 형식**: multipart/form-data로 `request`(application/json) + `video`(video/mp4) 2개 part. dio의 `MediaType`은 dio v5.7+에서 `DioMediaType`으로 재익스포트됨 — 따로 `http_parser`를 의존성에 추가하지 말 것.
- **영상 합본 내보내기 (구현 완료)**: 챌린지 확정 후 기록 영상들을 시간순으로 합쳐 1개 MP4 로 만드는 기능. 결정 사항은 [docs/handoff.md](docs/handoff.md) "영상 내보내기 회의록", 함정 모음은 같은 문서 "알려진 주의사항 / 함정" 참고. 합성은 **클라이언트 측 `ffmpeg_kit_flutter_new_video`** (LGPL 'video' 변종) 로 처리 — 서버 부담 0. 자막 디폴트는 `amount.memo` → 없으면 지출="내용 금액원" / 무지출="무지출" 순으로 폴백. **인코더는 sw `mpeg4` 만 사용** — `h264_mediacodec` 은 silent fail, `libx264` 는 GPL 이라 빌드에 없음, `libkvazaar` 는 native crash. 자세한 경로 [video_composer.dart](tenk_app/lib/data/export/video_composer.dart) `_videoEncoder` 주석 참고.

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
- **지출 기록**: `category`, `content` NOT BLANK, `amount > 0`, **영상 선택**. `spent_dt`는 클라이언트가 챌린지 기간 안의 임의 일시를 보낼 수 있다.
- **메모(`memo`, VARCHAR 500, NULL 허용)**: 지출/무지출 양쪽 모두 선택 입력. 사용자가 그 기록에 남기는 자유 텍스트. **빈 문자열/공백은 엔티티에서 null 로 정규화** (DTO 분기를 깔끔하게). 용도는 영상 export 자막 디폴트 오버라이드 — 메모 있으면 그 값, 없으면 지출="내용 금액원" / 무지출="무지출" 폴백.
- **무지출 기록**: `is_no_spend = true`, `amount = 0`, `category/content` NULL 허용, **영상 선택**. **제약 (도메인 정합성)**:
  - **일시 입력 불가** — 클라이언트가 보낸 `dateTime`은 서비스에서 무시되고 서버가 `LocalDateTime.now()`(분초까지)를 박는다. "오늘 하루 지출이 없다"는 행위만 의미 있으므로 과거/미래 무지출은 성립하지 않는다.
  - **하루 1회** — 같은 챌린지 + 같은 날에 두 번째 무지출 등록은 `AMOUNT_NO_SPEND_ALREADY_EXISTS`로 거부. 1차 방어선은 서비스 검증, 2차는 DB `uk_amount_no_spend_day` 생성 컬럼 UNIQUE 인덱스 ([docs/schema.sql](docs/schema.sql) `no_spend_day_key`).
  - **지출 등록 시 자동 삭제** — 같은 날 이미 무지출이 있는 상태에서 그 날에 지출이 등록되면, 무지출 row + 첨부 영상 파일까지 자동 삭제하고 `AmountRecordResult.removedNoSpendCount`로 클라이언트에 통지 (Flutter는 SnackBar로 "오늘 무지출 기록이 취소되었어요" 표기). 그 다음 `AmountRecordedEvent`가 발행돼 배지가 재평가된다.
- **수정** (`PUT /api/challenges/{cid}/amounts/{aid}`): 진행 중 챌린지에 한해 가능. 카드 탭 → 수정 화면 진입. 영상은 `videoAction` 으로 KEEP/REMOVE/REPLACE 중 하나 (REPLACE 면 새 video part 필수).
  - **지출**: 카테고리/내용/금액/메모/**시간만** 변경 가능. **날짜는 고정** — 서버는 클라이언트 `time` (HH:mm:ss) 만 받아서 기존 spentDt 의 LocalDate 와 결합한다. 날짜를 바꾸고 싶으면 삭제 후 재등록.
  - **무지출**: memo + 영상만. 카테고리/내용/금액/시간은 서버가 무시.
  - 배지 재평가는 안 한다. 날짜·noSpend 여부가 그대로라 STREAK/NO_SPEND 가 바뀔 일이 없음. (영상만 바꾸는 케이스도 동일.)
- **일시 의미**:
  - `spent_dt` (DATETIME, NOT NULL): 지출일 때만 사용자가 고른 "지출이 발생한 일시". **날짜 부분**이 챌린지 기간(`startDate`~`endDate`, 양끝 포함) 안에 있어야 함 (`AMOUNT_DATE_OUT_OF_RANGE`). 기본값은 지금. 배지·집계는 `spentDt.toLocalDate()`를 기준으로 잡는다. 무지출은 위 제약대로 서버 now() 강제.
  - `created_dt` (DATETIME, JPA Auditing): 서버가 자동으로 박는 row 생성 시각. 감사용. 도메인 로직에서 직접 쓰지 않는다.
- **응답 형태**: `POST /api/challenges/{cid}/amounts` 는 `AmountRecordResult { amount, removedNoSpendCount }`. `PUT` 은 갱신된 `AmountResponse` 단일. list/delete 는 기존대로 `AmountResponse` 직접.
- 챌린지가 시작 전이거나(`CHALLENGE_NOT_STARTED`) 종료된 상태(`CHALLENGE_ALREADY_FINISHED`)에서는 기록·수정 불가.

### 배지 (챌린지 단위)
배지는 **챌린지 1개에 귀속**된다. 같은 사용자가 챌린지 A 와 B 에서 똑같이 STREAK 7 을 얻으면
`challenge_badge` 행이 두 개 생긴다. 챌린지 응답(`ChallengeResponse.badges`)에 인라인으로 노출되며
별도 "내 배지" 화면은 없다. **유저 단위 누적(=업적, achievement) 시스템은 추후 별도 테이블로 추가 예정**
(현재 범위 밖).

- 단계: `condition_value` = **3 / 7 / 14 / 30** (CHALLENGE_SUCCESS 만 1).
- `STREAK`: **그 챌린지 안에서** 매일(지출 또는 무지출 무관) 기록한 **연속** 일수. 끊기면 의미가 퇴색되는 "꾸준함" 보상이라 연속 정의 유지.
- `NO_SPEND`: **그 챌린지 안에서** 기록이 무지출만 있는 날의 **누적** 일수. 끊겼다가 다시 무지출해도 합산된다 (절약 총량 보상). 같은 날 지출이 끼면 그 날은 카운트에서 빠진다. 챌린지 최대 30일이라 NO_SPEND 30 단계는 챌린지 모든 날이 무지출인 경우.
- `CHALLENGE_SUCCESS`: 챌린지가 성공으로 확정될 때 1회 지급.
- STREAK 끝나는 기준일: `min(today, challenge.endDate)`. 진행 중이면 today, 종료 후엔 endDate.
- **회수(revoke) 정책**: 재평가 시 현재 값이 조건 미달이면 이미 지급된 `challenge_badge` 도 DELETE. 예: 무지출 3일로 NO_SPEND 3 받은 뒤 그 중 하루에 지출이 추가돼 무지출 row 가 자동 삭제되면 → 누적 2일 → NO_SPEND 3 회수. `BadgeGrantService.applyLadder` 가 grant/revoke 양방향을 단일 패스로 처리.
- **지급 트리거 2종**:
  - 이벤트: `AmountRecordedEvent`(지출/무지출 기록 후 → 해당 챌린지 재평가), `ChallengeFinishedEvent`(챌린지 확정 후 → CHALLENGE_SUCCESS 지급 + 재평가) — `BadgeEventListener`가 `@TransactionalEventListener(AFTER_COMMIT)` + `@Transactional(REQUIRES_NEW)` 조합으로 처리. **REQUIRES_NEW가 필수**: AFTER_COMMIT 콜백 시점에는 원본 tx의 동기화가 정리 중이라 단순 REQUIRED 호출은 새 tx를 못 열고 쓰기가 조용히 사라진다 ([BadgeEventListener](tenk-backend/src/main/java/com/hjson/tenk/domain/badge/BadgeEventListener.java) 주석 + [BadgeEventIntegrationTest.grantChallengeSuccessDirectCall vs challengeSuccessGrantsBadge](tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeEventIntegrationTest.java)).
  - 배치: 매일 새벽 1시 활성 챌린지 전체 재평가 (`evaluateAllActive`, 이벤트 누락 대비).
- 데이터 모델: [challenge_badge](docs/schema.sql) `(challenge_id, badge_id)` UNIQUE. 한 챌린지 안에서 같은 배지는 1번만.

### 내보내기
- **JSON 통계 export** (`GET /api/challenges/{id}/export`): 일별·카테고리별 집계 + 전체 item 목록. 통계·외부 연동용으로 유지. 화면 구성은 클라이언트 몫.
- **영상 합본 export (구현 완료)**: 챌린지 확정 후 기록 영상을 시간순으로 합쳐 1개 MP4 로 내보내는 기능. 클라이언트 측 `ffmpeg_kit_flutter_new_video` 로 처리. 진입은 챌린지 상세 화면의 "영상 만들기" 카드 (확정 후에만 노출). 파이프라인은 ① 원본 영상 prefetch → ② 클립 단위 정규화(480x864 세로, 2초, 자막 PNG overlay 합성, mpeg4) → ③ 0.3초 xfade 로 concat → ④ 갤러리 저장(`gal`) + OS 공유(`share_plus`). **자막은 Flutter `TextPainter` 로 투명 PNG 를 그려 ffmpeg `overlay` 필터로 합성** — ffmpeg 8.0 drawtext 가 multi-codepoint 한글에서 첫 글리프만 그리고 뒤를 silent drop 시키는 회귀가 있어 (`text=`/`textfile=`/`text_shaping=0`/폰트 교체 모두 무효) drawtext 자체를 우회. 자세한 결정·범위·진단 경로는 [docs/handoff.md](docs/handoff.md) "영상 내보내기 회의록" 및 "함정 — drawtext 한글 회귀".

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
    └── badge/       (Badge, ChallengeBadge, BadgeGrantService, BadgeEventListener, BadgeScheduler, dto/AcquiredBadgeResponse)
                     <!-- 챌린지 단위. 응답은 ChallengeResponse.badges 에 인라인 — 별도 컨트롤러 없음 -->

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
│   ├── amount/                   # 지출/무지출 기록 + multipart 영상 업로드
│   │   ├── amount.dart, amount_api.dart
│   ├── badge/                    # 챌린지 응답에 인라인되는 AcquiredBadge 모델만 (API 없음)
│   │   └── badge.dart
│   ├── media/                    # 영상 다운로드 (export prefetch 용)
│   │   └── media_api.dart
│   └── export/                   # ffmpeg 영상 합본 합성 (외부 통신 X, 로컬 처리)
│       └── video_composer.dart     # 정규화→concat 2-pass. mpeg4 sw 인코더 고정
└── presentation/               # 화면. data 레이어를 Scope로만 호출
    ├── common/                   # 도메인 무관 공용 위젯·헬퍼
    │   ├── async_state.dart        # AsyncStateMixin + AsyncStateView (필수 — 아래 컨벤션 참고)
    │   └── error_view.dart
    ├── login/login_screen.dart
    ├── challenge/
    │   ├── _formatters.dart        # 도메인 내부 공유 (외부 노출 X — 언더스코어 prefix)
    │   ├── widgets/                # 도메인 전용 공용 위젯
    │   │   ├── challenge_status.dart
    │   │   ├── challenge_badges.dart  # 챌린지에 귀속된 배지 아이콘만 작게 (잠금 노출 X)
    │   │   └── badge_celebration_dialog.dart  # 신규 배지 획득 시 풀스크린 축하 모달 + 큐 헬퍼
    │   ├── export/                 # 영상 합본 export 흐름 (확정 후에만 진입)
    │   │   ├── export_plan.dart      # 세션 한정 모델 (선택 + 자막 오버라이드)
    │   │   ├── export_screen.dart    # 클립 선택 + 자막 편집
    │   │   ├── export_prefetch_screen.dart  # 원본 영상 다운로드
    │   │   ├── export_compose_screen.dart   # ffmpeg 합성 진행률 + 캔슬
    │   │   └── export_result_screen.dart    # 미리보기 + 갤러리 저장 + 공유
    │   └── *_screen.dart           # 카드·상세 양쪽에서 ChallengeBadgesRow 사용
    └── amount/                       # 기록 추가/수정 + 촬영 + 미리보기
        ├── amount_record_screen.dart    # 폼 (지출/무지출 토글). 카메라 인라인 없음 — VideoAttachmentSection 만 (즉시 모드)
        ├── amount_edit_screen.dart      # 카드 탭 → 진입. 시간/내용/메모/영상 수정 + 삭제. 서버 영상 lazy 다운로드 캐시 (`_serverVideoLocalPath`)
        ├── amount_camera_screen.dart    # 2초 녹화 + 녹화 후 video_player 자동 재생(loop). "사용" pop<String>(path)
        ├── amount_video_preview_screen.dart  # 기존/새 영상 전용 미리보기 화면. pop<VideoPreviewAction>(retake/delete)
        └── widgets/
            └── video_attachment_section.dart  # 영상 첨부 상태 위젯. `expandable=false` (record) 즉시 모드 / `expandable=true` (edit) "영상 보기" 버튼만
```

자산: `tenk_app/assets/fonts/Korean.ttf` (현재 미사용 — 영상 export 자막은 Flutter `TextPainter` + 시스템 폰트 폴백으로 처리. 자막 폰트를 명시 지정하고 싶으면 [tenk_app/assets/fonts/README.md](tenk_app/assets/fonts/README.md) 참고).

배지 자산: `tenk_app/assets/badges/` (pubspec.yaml `flutter.assets`에 등록). 파일명은 서버 `badge.icon_path`와 1:1 매칭 (`streak_3.png` 등 9개). 새 배지 추가 시 schema.sql · 자산 디렉토리 동시 갱신.

Lottie 자산: `tenk_app/assets/lottie/` — 현재 `confetti.json` (배지 축하 모달 컨페티) 1개. 파일이 없으면 컨페티만 조용히 생략되고 배지 줌·바운스는 그대로. 추가/교체 시 라이선스 확인 ([assets/lottie/README.md](tenk_app/assets/lottie/README.md)).

배지 UI 원칙:
- **챌린지에 귀속된 획득 배지만 노출** — 잠금 상태/미획득은 챌린지 단위 모델에서 의미 없으므로 보이지 않는다. 전용 "배지 화면"이나 진입점도 없다.
- 챌린지 응답(`Challenge.badges`)을 카드·상세에서 그대로 [ChallengeBadgesRow](tenk_app/lib/presentation/challenge/widgets/challenge_badges.dart) 로 렌더.
- **신규 배지 획득 알림은 [ChallengeDetailScreen](tenk_app/lib/presentation/challenge/challenge_detail_screen.dart) 의 reload diff 로만**. `_knownBadgeIds` (challengeBadgeId 기반) 와 새 응답을 비교해 신규 항목만 [showBadgeCelebrations](tenk_app/lib/presentation/challenge/widgets/badge_celebration_dialog.dart) 로 큐잉. 첫 로드는 `_baselineSet` 으로 막아 baseline 만 채움 — 과거 배지를 다시 축하하지 않는다. 메인/홈 등 다른 진입점에서도 알리고 싶으면 global `BadgeNotifier` 로 승격 (현재 범위 밖).
- 유저 단위 누적(=업적) 화면은 추후 추가 예정 — 그때 별도 `presentation/achievement/` + 별도 Scope/API 신설.

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
- **LAZY 연관 매핑된 엔티티를 응답 DTO로 변환할 때**: 컨트롤러가 트랜잭션 밖에서 매핑하면 `LazyInitializationException`. **컨트롤러에 `@Transactional` 붙이지 말고, repository 쿼리에서 `JOIN FETCH`로 같이 끌어와라.** N+1도 피한다. 회귀 가드는 `@SpringBootTest` 통합 테스트로 — 단위/`@DataJpaTest`는 못 잡는다 ([UserBadgeRepository.findByUserOrderByCreatedDtDesc](tenk-backend/src/main/java/com/hjson/tenk/domain/badge/UserBadgeRepository.java) + [BadgeControllerIntegrationTest.returnsAcquiredBadgesWithBadgeFieldsResolved](tenk-backend/src/test/java/com/hjson/tenk/domain/badge/BadgeControllerIntegrationTest.java) 패턴 참고).

## 코딩 컨벤션 — Flutter

- **화면의 비동기 로딩은 `AsyncStateMixin` + `AsyncStateView` 사용**. `FutureBuilder` 금지. 이유: `FutureBuilder`가 새 future로 교체돼도 stale snapshot으로 그리는 케이스가 있어 챌린지 생성/삭제 후 갱신이 누락된 적이 있음. mixin은 `_loading/_data/_error/_loadGen` 4-tuple과 stale-response 가드를 한 곳에 캡슐화한다. 한 화면이 두 종류 이상의 비동기 자원을 다루면 mixin 대신 직접 state를 들 것. ([presentation/common/async_state.dart](tenk_app/lib/presentation/common/async_state.dart))
- **HTTP 응답은 항상 `unwrapData` / `unwrapList` 통과**. 백엔드 envelope 풀이 로직을 도메인마다 복붙하지 말 것. ([data/api/api_response.dart](tenk_app/lib/data/api/api_response.dart))
- **에러는 SnackBar로 노출 시 `toApiException(e).message` 사용**. dio 에러·서버 에러·기타 예외를 일관된 한국어 메시지로 변환.
- **모델은 immutable + `fromJson` 팩토리**. `@immutable` 어노테이션 + `final` 필드. JSON 키는 백엔드 응답 그대로 (snake/camel 변환 X).
- **Navigator push/pop의 generic은 양쪽 모두 명시** (`push<T>(MaterialPageRoute<T>(...))`). push 결과에 의존하지 말고 push 종료 시점에 무조건 새로고침 — 결과 누락 케이스가 있음 ([docs/handoff.md](docs/handoff.md) "함정 — Flutter" 참고).
- **위젯 중복은 즉시 추출**: 두 화면이 같은 위젯을 쓰면 도메인 위젯은 `presentation/<domain>/widgets/`, 도메인 무관 공용 위젯은 `presentation/common/`에. 화면 파일 안에 `_PrivateView` 클래스로 두는 건 그 화면에서만 쓸 때.
- **Scaffold body 는 항상 `SafeArea(top: false, child: ...)` 로 감싼다** (AppBar 가 있는 화면 기준). 안드로이드 제스처 내비/3-버튼 바가 본문 하단 액션 버튼을 가리는 기기가 있어 일관 적용한다. AppBar 가 없는 화면(login 처럼)만 `SafeArea(child: ...)` 전체 방향. **bottomNavigationBar 슬롯은 Flutter 가 inset 자동 처리하므로 별도 SafeArea 불필요** (export_screen 의 기존 패턴은 historical — 새 화면에서 따라할 필요 없음). 화면별로 SafeArea 가 있는 곳·없는 곳이 섞이면 디바이스 따라 가림이 들쭉날쭉해진다.
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
flutter run    # 연결된 디바이스/에뮬레이터에서 실행 (기본 base URL = http://10.0.2.2:8080, 에뮬레이터 전용)
```

**백엔드 base URL은 `lib/config/api_config.dart` 의 `API_BASE_URL` dart-define 으로 주입**. 기본값은 안드로이드 에뮬레이터용 `http://10.0.2.2:8080`. 다른 타깃은 빌드 시 명시:
- iOS 시뮬레이터: `--dart-define=API_BASE_URL=http://localhost:8080`
- 같은 Wi-Fi 안의 안드로이드 실기기: `--dart-define=API_BASE_URL=http://<PC LAN IP>:8080`. 동시에 두 군데 손볼 것 — ① [network_security_config.xml](tenk_app/android/app/src/main/res/xml/network_security_config.xml) 의 `<domain>` 목록에 해당 IP 추가 (cleartext HTTP 허용), ② PC Windows 방화벽에서 inbound TCP 8080 허용. **IP가 바뀌면 두 파일 + run config 모두 같이 갱신**.

**VS Code Launch Configurations** ([.vscode/launch.json](.vscode/launch.json), git 추적 — 워크스페이스는 리포 루트 `tenk/` 에서 열림. `cwd: tenk_app` 으로 Flutter 프로젝트 잡음): Run/Debug 드롭다운에서 골라 F5. **백엔드는 IntelliJ 에서 `bootRun` 한 번 띄워두면 충분** — Spring Boot 가 `0.0.0.0:8080` 에서 듣고 있어 에뮬레이터/실기기 양쪽이 같은 프로세스로 들어간다.
- `tenk_app (emulator)` — `--dart-define=API_BASE_URL=http://10.0.2.2:8080`
- `tenk_app (device)` — `--dart-define=API_BASE_URL=http://192.168.0.7:8080`. IP 는 이 머신·이 네트워크 기준 — 다른 환경에서는 [docs/handoff.md](docs/handoff.md) "PC LAN IP" 항목을 보고 launch.json + network_security_config 같이 갱신할 것

## 위치별 책임 (요약)

| 변경 위치 | 동시에 챙겨야 할 곳 |
|---|---|
| 엔티티 컬럼 추가 | `docs/schema.sql` 수동 동기화 (validate 모드라 안 맞으면 부팅 실패) |
| 새 도메인 추가 | 패키지 분리 (`domain/<name>/`), `ErrorCode`에 도메인 prefix 코드 추가 |
| 새 이벤트 추가 | `*Event` record는 도메인의 `event/` 하위에, 리스너는 소비자 도메인에 |
| 로그인 공급자 추가 | 공급자별 토큰 검증기(현 `KakaoTokenVerifier` 패턴) + `AuthService`에 분기 + `AuthProvider` enum 추가 + 신규 엔드포인트 `POST /api/auth/<provider>/login`. **브라우저 OAuth redirect 흐름은 사용하지 않음** (모바일 SDK + 토큰 교환 전제) |
| 파일 업로드 | 항상 `LocalFileStorage.store(file, subdir)`을 거치기. 경로를 직접 조립하지 말 것. **호출 전에 null/empty 분기는 도메인에서 하기** — `store()` 는 빈 파일이 들어오면 프로그래머 오류로 `INVALID_INPUT` 을 던진다 |
| amount 기록 수정 | `PUT /api/challenges/{cid}/amounts/{aid}` ([AmountController.update](tenk-backend/src/main/java/com/hjson/tenk/domain/amount/AmountController.java)). 지출은 시간만, 무지출은 memo + 영상만 갱신. 영상은 `videoAction` (KEEP/REMOVE/REPLACE) 로 분기. Flutter 진입은 챌린지 상세의 [_AmountTile.onTap](tenk_app/lib/presentation/challenge/challenge_detail_screen.dart) → [AmountEditScreen](tenk_app/lib/presentation/amount/amount_edit_screen.dart). 영상 섹션은 record 와 같은 [VideoAttachmentSection](tenk_app/lib/presentation/amount/widgets/video_attachment_section.dart) 을 공유하지만 `expandable: true` 로 collapsed 노출 — "영상 보기" 탭 시 [AmountVideoPreviewScreen](tenk_app/lib/presentation/amount/amount_video_preview_screen.dart) 푸시 후 `VideoPreviewAction` 으로 retake/delete 반환 |
| 환경별로 다른 값 추가 | 공통은 `application.yaml`, 환경별 override는 `application-{local,prod}.yaml`. prod placeholder는 TODO 주석 유지 |
| 보호된 신규 엔드포인트 추가 | 기본적으로 인증 필요 (`SecurityConfig.PERMIT_ALL`에 없으면 자동 보호). 컨트롤러는 `@CurrentUserId Long userId`로 사용자 식별 |
| 백엔드 도메인/서비스 추가 | `src/test/java/com/hjson/tenk/domain/<name>/` 아래에 단위 테스트도 같이. 패턴은 기존 6개 테스트 (`ChallengeTest`, `ChallengeServiceTest`, `AmountServiceTest`, ...) 참고. 의존 repository는 Mockito `@Mock` + `@InjectMocks`, 도메인 entity는 정적 팩토리로 만들고 id 등 사후 박을 필드는 `ReflectionTestUtils.setField`. `LocalDate.now()` 모킹 불가 — "종료된 챌린지" 같은 상태는 invariant 통과 후 reflection으로 endDate 사후 박는 패턴 (`ChallengeServiceTest.finishedChallenge` 참고) |
| 새 이벤트 리스너 추가 | `@TransactionalEventListener(AFTER_COMMIT)`로 DB 쓰기를 한다면 리스너 메서드에 **반드시 `@Transactional(propagation = Propagation.REQUIRES_NEW)`** 같이 박을 것. 안 박으면 쓰기가 조용히 사라짐 ([BadgeEventListener](tenk-backend/src/main/java/com/hjson/tenk/domain/badge/BadgeEventListener.java) 참고). 검증은 `@SpringBootTest` 통합 테스트로 — 단위 테스트는 못 잡는다 |
| 백엔드 통합 테스트 추가 | [IntegrationTestBase](tenk-backend/src/test/java/com/hjson/tenk/support/IntegrationTestBase.java) 상속. `@SpringBootTest` + `@ActiveProfiles("test")` + 트랜잭션 롤백 대신 `@BeforeEach`로 비-마스터 테이블 DELETE. **테스트 메서드 자체는 `@Transactional` 금지** — AFTER_COMMIT이 안 도는 함정 ([handoff.md §1·§2 검증 메모](docs/handoff.md)). 트랜잭션이 필요하면 `tx.execute(status -> ...)`로 명시 |
| 인증/필터 슬라이스 테스트 추가 | [JwtAuthenticationFilterWebMvcTest](tenk-backend/src/test/java/com/hjson/tenk/security/JwtAuthenticationFilterWebMvcTest.java) 패턴. `@WebMvcTest(SomeController.class)` + `@Import({SecurityConfig.class, JwtAuthenticationFilter.class, JwtTokenProvider.class})` + `@EnableConfigurationProperties(AuthProperties.class)` + `@TestPropertySource`로 jwt secret 주입. 컨트롤러 협력자는 `@MockitoBean`. **Spring Boot 4 함정**: `WebMvcTest` import 가 `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest` 로 이동했다 (구 `...test.autoconfigure.web.servlet.WebMvcTest` 아님). 만료 토큰은 TTL 기반 `JwtTokenProvider`로 못 만드니까 같은 시크릿으로 `Jwts.builder()` 직접 호출해 expiration 만 과거로 박는다 |
| Flutter 새 도메인 추가 | ① 데이터: `lib/data/<feature>/<feature>.dart`(모델, `@immutable` + `fromJson`) + `<feature>_api.dart`(authDio 주입, `unwrapData`/`unwrapList` 사용). 여러 출처를 합쳐야 하면 `<feature>_repository.dart`도. ② DI: `lib/app/scopes.dart`에 `<Feature>Scope` 추가 + `main.dart`에서 인스턴스 생성·주입. ③ 화면: `lib/presentation/<feature>/<feature>_screen.dart`. 데이터 호출은 `<Feature>Scope.of(context)`로만 |
| Flutter 새 자산(이미지/폰트) 추가 | `tenk_app/assets/<feature>/` 아래에 두고 `tenk_app/pubspec.yaml`의 `flutter.assets`에 디렉토리(끝에 `/`) 등록. 디렉토리 등록은 그 안의 파일이 추가될 때 자동 인식. **새 자산은 hot reload 안 됨** — `R`(hot restart)로 반영. 자산이 없을 수도 있는 개발 중에는 `Image.asset(... errorBuilder:)`로 폴백 위젯을 두면 화면이 안 깨짐 ([badge_list_screen.dart](tenk_app/lib/presentation/badge/badge_list_screen.dart) `_IconFallback` 참고) |
| 배지 카탈로그 변경 | 서버는 `badge` 테이블의 9행(STREAK 3/7/14/30, NO_SPEND 3/7/14/30, CHALLENGE_SUCCESS 1)으로 고정. 새 단계/타입 추가 시 **네 곳을 동시에 갱신**: ① [docs/schema.sql](docs/schema.sql)의 INSERT (+ DB에 수동 적용) ② [tenk_app/lib/data/badge/badge.dart](tenk_app/lib/data/badge/badge.dart)의 `BadgeType` enum (label 매핑까지) ③ [tenk_app/assets/badges/](tenk_app/assets/badges/)에 아이콘 파일 ④ [_NoSpendTodayCard._ladder](tenk_app/lib/presentation/challenge/challenge_detail_screen.dart) 의 NO_SPEND 단계 배열 (성취감 카드 게이지가 사다리로 사용). **챌린지 단위라 클라에 카탈로그 전체를 두지 않는다** — 획득한 것만 챌린지 응답에 인라인되므로 미획득 노출 위젯이 없음 |
| 배지를 부여하는 로직 변경 | [BadgeGrantService](tenk-backend/src/main/java/com/hjson/tenk/domain/badge/BadgeGrantService.java) 는 항상 **챌린지 단위**로 평가. `evaluateForChallenge(challengeId)` / `grantChallengeSuccess(challengeId, result)`. 유저 단위 누적이 필요하면 새 서비스(추후 achievement 시스템)로 분리할 것 — 여기에 user 파라미터를 다시 끼우지 말 것. amount 쿼리는 `findByChallengeOrderBySpentDtAscCreatedDtAsc(challenge)` 사용. **STREAK는 연속, NO_SPEND는 누적** (서로 다른 행동에 대한 보상이라 정의가 다름). 단일 패스 `applyLadder` 가 grant/revoke 양방향을 처리 — 회수가 필요한 변경(예: 무지출 자동 삭제)에서도 별도 호출 없이 재평가만 하면 정합. |
| Flutter 새 화면의 비동기 로딩 | `AsyncStateMixin<W, T>` + `AsyncStateView<T>` 사용 ([presentation/common/async_state.dart](tenk_app/lib/presentation/common/async_state.dart)). `FutureBuilder` 금지. `fetch()` 오버라이드 + `didChangeDependencies`에서 `ensureLoaded()`. 외부 동작 결과를 즉시 반영하려면 `replaceData(next)`, 그 외 갱신은 `reload()`. 에러는 `toApiException(e).message`로 SnackBar 노출 |
| Flutter 새 공용 위젯 | 두 화면 이상이 같은 위젯을 쓰면 즉시 추출. 도메인 전용은 `presentation/<domain>/widgets/`, 도메인 무관은 `presentation/common/` |
| camera 패키지 fork 갱신 | [tenk_app/vendor/camera_patched/camera_android_camerax](tenk_app/vendor/camera_patched/camera_android_camerax) 가 업스트림 `camera_android_camerax` 의 fork. `pubspec.yaml` `dependency_overrides` 로 주입. **패치 두 군데**: `initializeCamera` 의 `bindToLifecycle` 리스트 (`imageAnalysis` 자리에 `videoCapture` 를 넣음) + `stopVideoRecording` 의 `_unbindUseCaseFromLifecycle(videoCapture!)` 제거. 둘 다 `[tenk fork patch]` 주석으로 표시. **사유**: 업스트림은 VideoCapture 를 lazy bind 라 매 녹화 시작마다 Camera2 capture session 이 재구성돼 preview freeze. eager bind 로 전환해 freeze 자체 제거. Tenk 가 image stream 을 안 써서 ImageAnalysis 를 lazy 로 미뤄도 무해. **업스트림 버전 올릴 때**: pub cache 에서 신버전 디렉토리 통째로 vendor 에 덮어쓰고 두 지점 재적용. CameraX UseCase 조합 표 ([공식 문서](https://developer.android.com/media/camera/camerax/architecture#combine-use-cases)) 기준 P+IC+VC 는 LIMITED 이상 지원 — 4-way 는 LEVEL_3 한정이므로 ImageAnalysis 를 같이 추가하지 말 것 |
| 영상 export 합성 파이프라인 변경 | [VideoComposer](tenk_app/lib/data/export/video_composer.dart) 에서 ffmpeg 명령 구성. **인코더는 sw `mpeg4` 고정 — 바꾸지 말 것**. `h264_mediacodec`(hw silent fail) / `libx264`(GPL · 빌드 미포함) / `libkvazaar`(native crash) 모두 실격됐고 경로는 `_videoEncoder` 주석 + [handoff.md "함정 — H.264/HEVC sw 인코더 다 막힘"](docs/handoff.md) 에 박혀 있다. **자막은 ffmpeg drawtext 대신 Flutter `TextPainter` 로 PNG 그려 `overlay` 필터로 합성 — drawtext 로 회귀하지 말 것** (ffmpeg 8.0 의 multi-codepoint 한글 silent drop 회귀, [handoff.md "함정 — drawtext 한글 회귀"](docs/handoff.md) 참고). 자막 좌표/폰트크기/박스 스타일은 `_drawTextBlock` 안에서 조절. 합성 파라미터(해상도/비트레이트/xfade 길이 등)는 모두 클래스 상단 상수 |

## 미해결/다음 단계

진행 상태와 남은 작업은 [docs/handoff.md](docs/handoff.md) 참고.
