import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../../presentation/challenge/export/export_plan.dart';

/// 영상 합본 합성 서비스. ffmpeg_kit_flutter_new_video (LGPL) 위에 얇게 올린 래퍼.
///
/// 파이프라인 (2-pass):
///  1. **normalize**: 클립 단위로 480x864 (세로) / 2초 / 자막+대시보드 burn-in / MPEG-4 Part 2(`mpeg4`)
///     로 정규화. 텍스트 카드 클립(무지출+영상없음)은 ffmpeg `color` lavfi 소스로 검은 배경 생성.
///  2. **concat**: 정규화된 클립들을 0.3초 cross-fade 로 이어붙임. 출력은 MPEG-4 Part 2 / yuv420p / -an,
///     MP4 컨테이너.
///
/// 2-pass 인 이유: 입력 영상의 원본 해상도/SAR/fps 가 디바이스마다 달라 단일 `filter_complex` 로
/// 처리하면 디버깅이 지옥. 정규화 통과 후엔 모든 클립이 동일 스펙이라 concat 이 단순해진다.
///
/// **회의 결정 매핑**: #5(자막 하단 고정), #6(대시보드 Day N + 잔여), #7(잔여=클립 후 값 고정 — 카운트
/// 다운은 다음 이터레이션), #8(텍스트 카드 2초), #9(0.3초 xfade 무음), #10(480p).
class VideoComposer {
  VideoComposer();

  // 모바일 카메라가 세로로 녹화하므로 출력도 세로(480x864 = 9:16에 가까운 5:9). 가로 출력이면
  // 좌우에 검은 패딩이 생긴다.
  // 864 = 16×54, 480 = 16×30 — 16-pixel 정렬이라 sw 인코더 안정성 OK.
  static const int _outWidth = 480;
  static const int _outHeight = 864;
  static const double _clipDurationSec = 2.0;
  static const double _xfadeDurationSec = 0.3;
  static const double _resultCardDurationSec = 3.0;
  static const String _videoBitrate = '1500k';

  // ffmpeg 내장 MPEG-4 Part 2 sw 인코더. LGPL, 외부 라이브러리 의존 0, 검증된 안정성.
  //
  // **여기까지 온 경로** — 다음 인코더들이 모두 실격됐다:
  //  - `h264_mediacodec` (hw): lavfi color 소스/짧은 클립에서 return code 0 + duration N/A +
  //    stream 없음으로 silent fail. concat 시 `[N:v] matches no streams` 발생.
  //  - `libx264` (sw H.264): GPL — 현재 'video' 변종 빌드에 미포함, 라이센스 이슈.
  //  - `libkvazaar` (sw HEVC): ffmpeg_kit_flutter_new_video 빌드에서 cleanup 시 native crash
  //    (`pthread_mutex_destroy called on a destroyed mutex` in `avcodec_free_context`).
  //    kvazaar 자체 스레드풀과 ffmpeg exit_program 의 더블 프리 충돌. 패키지 버그라 우회 불가.
  //
  // 단점: 같은 비트레이트에서 H.264/HEVC 보다 효율 떨어짐. 2초 480p 짜리라 실측 차이는 미미.
  static const String _videoEncoder = 'mpeg4';
  static const String _outPixFmt = 'yuv420p';

  FFmpegSession? _currentSession;
  bool _cancelled = false;

  /// 합본 영상을 만든다. 진행 상황은 [onPhase] 로 단계별 알림 (텍스트 + 0~1 진척도).
  /// 결과 파일 경로 반환. 도중 [cancel] 호출하면 [VideoComposeCancelled] 던짐.
  ///
  /// [outputPath] 가 이미 있으면 덮어쓴다 (회의 결정 #13 캐싱 X).
  ///
  /// [resultCardPngPath] 가 non-null 이면 정규화된 마지막 클립으로 결과 카드 PNG 를 3초 정지 화면
  /// (`_resultCardDurationSec`) 으로 추가한 뒤 concat. PNG 는 480x864 (영상 export 해상도와 1:1) 가 가정.
  Future<String> compose({
    required ExportPlan plan,
    required int challengeTargetAmount,
    required DateTime challengeStartDate,
    required String outputPath,
    required void Function(ComposeProgress progress) onPhase,
    String? resultCardPngPath,
  }) async {
    _cancelled = false;

    if (plan.clips.isEmpty) {
      throw const VideoComposeFailed('합본에 포함된 클립이 없어요.');
    }

    final tmpDir = await _ensureWorkDir(challengeStartDate);
    final normalizedPaths = <String>[];
    final clipDurations = <double>[];
    final totalNormalizeSteps =
        plan.clips.length + (resultCardPngPath != null ? 1 : 0);

    // 1. Pass 1 — 클립별 정규화. 자막은 Flutter TextPainter 로 PNG 그려 overlay 합성 (drawtext 미사용).
    final dashboardTexts = _buildDashboardTexts(plan, challengeTargetAmount, challengeStartDate);
    for (var i = 0; i < plan.clips.length; i++) {
      _throwIfCancelled();
      onPhase(ComposeProgress(
        phase: ComposePhase.normalizing,
        currentIndex: i,
        totalCount: totalNormalizeSteps,
        message: '클립 정규화 ${i + 1}/${plan.clips.length}',
      ));
      final clip = plan.clips[i];
      final outPath = '${tmpDir.path}/norm_$i.mp4';
      await _normalizeClip(
        clip: clip,
        dashboardText: dashboardTexts[i],
        outputPath: outPath,
      );
      normalizedPaths.add(outPath);
      clipDurations.add(_clipDurationSec);
    }

    // 1.5. 결과 카드 (선택) — 정지 화면 3초. PNG 가 480x864 이라 scale/pad 는 사실상 noop 이지만
    // 다른 입력 케이스를 위해 안전망으로 유지.
    if (resultCardPngPath != null) {
      _throwIfCancelled();
      onPhase(ComposeProgress(
        phase: ComposePhase.normalizing,
        currentIndex: plan.clips.length,
        totalCount: totalNormalizeSteps,
        message: '결과 카드 추가',
      ));
      final cardOut = '${tmpDir.path}/norm_card.mp4';
      await _normalizeStaticImageClip(
        inputPng: resultCardPngPath,
        durationSec: _resultCardDurationSec,
        outputPath: cardOut,
      );
      normalizedPaths.add(cardOut);
      clipDurations.add(_resultCardDurationSec);
    }

    // 3. Pass 2 — concat with xfade. 클립 1개면 그냥 복사.
    _throwIfCancelled();
    onPhase(const ComposeProgress(
      phase: ComposePhase.concatenating,
      currentIndex: 0,
      totalCount: 1,
      message: '영상 합치는 중',
    ));
    if (normalizedPaths.length == 1) {
      await File(normalizedPaths.single).copy(outputPath);
    } else {
      await _concatWithXfade(
        inputs: normalizedPaths,
        durations: clipDurations,
        outputPath: outputPath,
      );
    }

    onPhase(const ComposeProgress(
      phase: ComposePhase.done,
      currentIndex: 1,
      totalCount: 1,
      message: '완료',
    ));
    return outputPath;
  }

  /// 외부에서 호출. 다음 [_throwIfCancelled] 체크 시점 또는 현재 ffmpeg 세션에서 즉시 중단.
  Future<void> cancel() async {
    _cancelled = true;
    final session = _currentSession;
    if (session != null) {
      await session.cancel();
    }
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const VideoComposeCancelled();
  }

  Future<Directory> _ensureWorkDir(DateTime challengeStartDate) async {
    final tmp = await getTemporaryDirectory();
    // tenk_export 하위에 별도 work 디렉토리. challengeStartDate 는 단순 키로만 사용.
    final dir = Directory(
      '${tmp.path}/tenk_export/work_${challengeStartDate.millisecondsSinceEpoch}',
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    return dir;
  }

  /// 클립별 대시보드 텍스트 ("Day N · 잔여 X,XXX원"). 시간 순서 가정. 무지출이면 잔액 변화 없음.
  List<String> _buildDashboardTexts(
      ExportPlan plan, int targetAmount, DateTime startDate) {
    final startKey =
        DateTime(startDate.year, startDate.month, startDate.day);
    int running = 0;
    final out = <String>[];
    for (final clip in plan.clips) {
      final src = clip.source;
      if (!src.noSpend) {
        running += src.amount;
      }
      final balance = targetAmount - running;
      final clipDate =
          DateTime(src.spentDt.year, src.spentDt.month, src.spentDt.day);
      final day = clipDate.difference(startKey).inDays + 1;
      out.add('Day $day · 잔여 ${_formatWon(balance)}');
    }
    return out;
  }

  Future<void> _normalizeClip({
    required ExportClipPlan clip,
    required String dashboardText,
    required String outputPath,
  }) async {
    // 자막은 Flutter TextPainter 로 PNG 를 만들고 ffmpeg overlay 로 합성한다.
    // 사유: ffmpeg 8.0 drawtext 가 multi-codepoint 한글에서 첫 글리프만 그리고 뒤를 silent drop 시키는
    // 회귀가 있어 (text_shaping=0/expansion=none 모두 무효). PNG overlay 는 텍스트 렌더링을 Flutter/Skia
    // 에 맡겨서 그 경로 자체를 우회. 자세한 진단 경로는 [docs/handoff.md](docs/handoff.md) 참고.
    final textPngPath = '$outputPath.text.png';
    await _renderTextOverlayPng(
      dashboardText: dashboardText,
      subtitleText: clip.comment,
      outputPath: textPngPath,
    );

    final localPath = clip.localVideoPath;
    final pngEsc = _escapePath(textPngPath);
    final outEsc = _escapePath(outputPath);
    final List<String> cmd;
    if (localPath != null) {
      // 영상 클립: scale+pad → SAR 정리 → 자막 PNG overlay → 인코더 픽셀 포맷 정합.
      final inEsc = _escapePath(localPath);
      cmd = [
        '-y',
        '-i', inEsc,
        '-i', pngEsc,
        '-t', _clipDurationSec.toString(),
        '-filter_complex',
        '[0:v]scale=$_outWidth:$_outHeight:force_original_aspect_ratio=decrease,'
            'pad=$_outWidth:$_outHeight:(ow-iw)/2:(oh-ih)/2:black,'
            'setsar=1[v];'
            '[v][1:v]overlay=0:0:format=auto,format=$_outPixFmt[outv]',
        '-map', '[outv]',
        '-an',
        '-c:v', _videoEncoder,
        '-b:v', _videoBitrate,
        '-r', '30',
        outEsc,
      ];
    } else {
      // 텍스트 카드: lavfi color 소스 + 자막 PNG overlay. 회의 결정 #8 (무지출+영상없음 → 2초 텍스트 카드).
      cmd = [
        '-y',
        '-f', 'lavfi',
        '-i', 'color=c=black:s=${_outWidth}x$_outHeight:d=$_clipDurationSec:r=30',
        '-i', pngEsc,
        '-filter_complex',
        '[0:v][1:v]overlay=0:0:format=auto,format=$_outPixFmt[outv]',
        '-map', '[outv]',
        '-an',
        '-c:v', _videoEncoder,
        '-b:v', _videoBitrate,
        outEsc,
      ];
    }

    await _runFfmpeg(cmd);
  }

  /// 480x864 투명 PNG 위에 대시보드(상단) + 자막(하단) + 반투명 박스를 그려 [outputPath] 에 저장.
  /// 픽셀 좌표·폰트 크기는 기존 drawtext 와 동일하게 맞춤 (24px top margin, 32px bottom margin,
  /// dashboard fontsize=28, subtitle fontsize=32, box padding=10, boxcolor=black@0.55).
  Future<void> _renderTextOverlayPng({
    required String dashboardText,
    required String subtitleText,
    required String outputPath,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _outWidth.toDouble(), _outHeight.toDouble()),
    );

    _drawTextBlock(canvas, dashboardText, fontSize: 28, topY: 24);
    _drawTextBlock(
      canvas,
      subtitleText,
      fontSize: 32,
      bottomY: _outHeight - 32,
    );

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(_outWidth, _outHeight);
      try {
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw const VideoComposeFailed('자막 PNG 변환 실패 (byteData null)');
        }
        await File(outputPath)
            .writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// 흰 글자 + 반투명 검정 박스. [topY] 또는 [bottomY] 중 하나만 지정 (anchor).
  void _drawTextBlock(
    ui.Canvas canvas,
    String text, {
    required double fontSize,
    double? topY,
    double? bottomY,
  }) {
    assert((topY == null) != (bottomY == null), 'topY 또는 bottomY 둘 중 하나만');
    const padding = 10.0; // drawtext boxborderw=10 과 동일

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    painter.layout(maxWidth: _outWidth.toDouble() - 2 * padding - 20);

    final textX = (_outWidth - painter.width) / 2;
    final textY = topY ?? (bottomY! - painter.height);

    final boxRect = Rect.fromLTWH(
      textX - padding,
      textY - padding,
      painter.width + padding * 2,
      painter.height + padding * 2,
    );
    final boxPaint = Paint()..color = const Color(0x8C000000); // black @ 0.55
    canvas.drawRect(boxRect, boxPaint);

    painter.paint(canvas, Offset(textX, textY));
    painter.dispose();
  }

  /// 결과 카드 PNG 같은 정지 이미지를 [durationSec] 길이의 클립으로 정규화. lavfi color 분기와 비슷하지만
  /// 자막 overlay 가 없고, 이미지 자체가 콘텐츠라 그대로 scale/pad 만 통과시킨다 (480x864 PNG 라 noop).
  Future<void> _normalizeStaticImageClip({
    required String inputPng,
    required double durationSec,
    required String outputPath,
  }) async {
    final inEsc = _escapePath(inputPng);
    final outEsc = _escapePath(outputPath);
    final cmd = [
      '-y',
      '-loop', '1',
      '-i', inEsc,
      '-t', durationSec.toString(),
      '-vf',
      'scale=$_outWidth:$_outHeight:force_original_aspect_ratio=decrease,'
          'pad=$_outWidth:$_outHeight:(ow-iw)/2:(oh-ih)/2:black,'
          'setsar=1,format=$_outPixFmt',
      '-an',
      '-c:v', _videoEncoder,
      '-b:v', _videoBitrate,
      '-r', '30',
      outEsc,
    ];
    await _runFfmpeg(cmd);
  }

  Future<void> _concatWithXfade({
    required List<String> inputs,
    required List<double> durations,
    required String outputPath,
  }) async {
    assert(inputs.length == durations.length);
    // xfade 체이닝: 각 transition 의 offset 은 이전까지 체인 길이 - overlap.
    // 클립 길이가 가변이라 (결과 카드 3초 등) 누적값을 클립별 duration 으로 계산해야 한다.
    final overlap = _xfadeDurationSec;

    final args = <String>['-y'];
    for (final p in inputs) {
      args.addAll(['-i', _escapePath(p)]);
    }

    final buf = StringBuffer();
    String prev = '[0:v]';
    double seqLen = durations[0];
    for (var i = 1; i < inputs.length; i++) {
      final next = '[$i:v]';
      // 마지막 xfade 출력도 일단 중간 라벨로 받고, 뒤에서 format= 으로 통일해 [outv] 로 보낸다.
      final xfadeOut = '[x$i]';
      final offset = seqLen - overlap;
      buf.write(
          '$prev${next}xfade=transition=fade:duration=$overlap:offset=${offset.toStringAsFixed(2)}$xfadeOut;');
      prev = xfadeOut;
      seqLen += durations[i] - overlap;
    }
    // 인코더 픽셀 포맷 정합 — mpeg4 는 yuv420p 가 정공법.
    buf.write('${prev}format=$_outPixFmt[outv]');

    args.addAll([
      '-filter_complex', buf.toString(),
      '-map', '[outv]',
      '-an',
      '-c:v', _videoEncoder,
      '-b:v', _videoBitrate,
      _escapePath(outputPath),
    ]);

    await _runFfmpeg(args);
  }

  Future<void> _runFfmpeg(List<String> args) async {
    _throwIfCancelled();
    final session = await FFmpegKit.executeWithArguments(args);
    _currentSession = session;
    final code = await session.getReturnCode();
    _currentSession = null;
    if (_cancelled || ReturnCode.isCancel(code)) {
      throw const VideoComposeCancelled();
    }
    if (!ReturnCode.isSuccess(code)) {
      // 출력 로그를 일부 담아서 디버그 친화적으로.
      final log = await session.getAllLogsAsString() ?? '';
      final trimmed =
          log.length > 800 ? '${log.substring(log.length - 800)}…' : log;
      throw VideoComposeFailed('ffmpeg 실패 (code=${code?.getValue()}). 로그 끝부분:\n$trimmed');
    }
  }

  /// Windows 백슬래시 경로를 ffmpeg 가 받아먹는 형태로 — 일단 그대로 통과
  /// (대부분의 dart:io 경로는 `/` 로 정상). 향후 Windows 환경 테스트 시 다시 점검.
  static String _escapePath(String input) => input.replaceAll('\\', '/');

  static String _formatWon(int amount) {
    final negative = amount < 0;
    final digits = amount.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${negative ? '-' : ''}${buf.toString()}원';
  }
}

enum ComposePhase { normalizing, concatenating, done }

class ComposeProgress {
  const ComposeProgress({
    required this.phase,
    required this.currentIndex,
    required this.totalCount,
    required this.message,
  });

  final ComposePhase phase;
  final int currentIndex;
  final int totalCount;
  final String message;

  /// 정규화 단계가 전체 진행률의 80%, concat 이 20% 라고 가정 — 단계별 가중치.
  double get overall {
    if (totalCount == 0) return 0.0;
    final clipFraction =
        (currentIndex / totalCount).clamp(0.0, 1.0).toDouble();
    return switch (phase) {
      ComposePhase.normalizing => clipFraction * 0.8,
      ComposePhase.concatenating => 0.8 + clipFraction * 0.2,
      ComposePhase.done => 1.0,
    };
  }
}

class VideoComposeCancelled implements Exception {
  const VideoComposeCancelled();
  @override
  String toString() => 'VideoComposeCancelled';
}

class VideoComposeFailed implements Exception {
  const VideoComposeFailed(this.message);
  final String message;
  @override
  String toString() => 'VideoComposeFailed: $message';
}
