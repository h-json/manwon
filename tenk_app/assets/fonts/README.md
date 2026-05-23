# (현재 미사용) 영상 export 자막 폰트

**현재 코드는 이 디렉토리의 폰트 파일을 쓰지 않는다.** 영상 합본 export 의 자막·대시보드는
[video_composer.dart](../../lib/data/export/video_composer.dart) 에서 Flutter `TextPainter` 로 PNG 를
그린 뒤 ffmpeg `overlay` 필터로 합성하는데, Flutter/Skia 가 Android 시스템 폰트 (Noto Sans CJK 등)
폴백으로 한글을 렌더하므로 별도 폰트 자산이 필요 없다.

`Korean.ttf` 파일은 [pubspec.yaml](../../pubspec.yaml) 의 `flutter.assets` 에 디렉토리 단위로 묶여
번들되지만 런타임에 로드하지 않는다. 자막 폰트를 시스템 폴백 대신 명시적으로 박고 싶을 때 이 자산을
재활용하면 된다.

## 명시적 폰트로 바꾸고 싶을 때

1. `pubspec.yaml` 의 `flutter:` 아래에 `fonts:` 섹션 추가:
   ```yaml
   fonts:
     - family: TenkExportFont
       fonts:
         - asset: assets/fonts/Korean.ttf
   ```
2. [video_composer.dart](../../lib/data/export/video_composer.dart) 의 `_drawTextBlock` 에서
   `TextStyle(... fontFamily: 'TenkExportFont')` 로 박는다.
3. cold restart (자산/pubspec 변경은 hot reload/restart 로 안 잡힘).

## 히스토리

원래 이 디렉토리는 ffmpeg `drawtext` 의 `fontfile=` 인자용이었지만, ffmpeg 8.0 drawtext 에 multi-codepoint
한글이 첫 글리프 이후 silent drop 되는 회귀가 있어 (`text=`, `textfile=`, `text_shaping=0`, font 교체 모두
무효) PNG overlay 로 갈아엎으면서 ffmpeg 측 폰트 사용을 폐기. 자세한 회의록·진단 경로는
[docs/handoff.md](../../../docs/handoff.md) "영상 내보내기 회의록" 및 "함정 — drawtext 한글 회귀" 참고.
