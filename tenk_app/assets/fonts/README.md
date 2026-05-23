# 한글 폰트 (영상 export drawtext 용)

이 디렉토리에 한글을 지원하는 TTF 파일을 `Korean.ttf` 라는 이름으로 두면 영상 합본
export 의 자막·대시보드가 사용한다. ffmpeg `drawtext` 가 폰트 파일 경로를 요구하기 때문에
시스템 폰트 대신 앱 자산으로 번들해야 한다.

## 추천

- **Pretendard Variable** (~600KB, OFL) — `Pretendard-Regular.ttf` 다운로드 후 `Korean.ttf` 로 이름 변경
  - https://github.com/orioncactus/pretendard/releases
- **NotoSansKR-Regular.ttf** (~3MB, OFL) — Google Fonts
  - https://fonts.google.com/noto/specimen/Noto+Sans+KR

OTF 포맷은 ffmpeg/libfreetype 일부 빌드에서 문제가 나니 **TTF 권장**.

## 없을 때 동작

폰트 파일이 없으면 [video_composer.dart](../../lib/data/export/video_composer.dart)
가 `MissingFontException` 을 던지고 export 화면은 안내 메시지를 띄운다. 합본 자체는 생성
되지 않는다 — 회의 결정 #12 (부분 합본 안 만들기) 와 일치.
