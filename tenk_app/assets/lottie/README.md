## Lottie 자산

배지 획득 축하 모달에서 사용하는 컨페티 애니메이션을 여기에 둔다.

### 필요한 파일

| 파일명 | 용도 |
|---|---|
| `confetti.json` | 배지 획득 축하 모달의 전면 컨페티 (1회 재생) |

### 추천 출처

- [LottieFiles](https://lottiefiles.com/) — "confetti" 검색. **무료(Free) 라이선스만** 사용. JSON 다운로드 후 `confetti.json` 으로 저장.
- 코드 측 폴백: 파일이 없거나 디코딩 실패 시 [badge_celebration_dialog.dart](../../lib/presentation/challenge/widgets/badge_celebration_dialog.dart) 가 컨페티만 조용히 생략하고 배지 줌·바운스는 정상 동작.

### 추가 시 체크
- 라이선스 확인 (특히 상용/배포 가능 여부)
- 파일 크기 — 보통 10~50KB 면 충분. 100KB 이상이면 다른 에셋으로 교체 고려.
- 새 Lottie 추가 시 pubspec.yaml 의 `flutter.assets` 는 디렉토리 단위 등록(`assets/lottie/`)이므로 별도 갱신 불필요.
