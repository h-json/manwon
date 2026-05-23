import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../presentation/challenge/export/export_plan.dart';

/// 영상 합본 합성 서비스. ffmpeg_kit_flutter_new_video (LGPL) 위에 얇게 올린 래퍼.
///
/// 파이프라인 (2-pass):
///  1. **normalize**: 클립 단위로 864x480 / 2초 / 자막+대시보드 burn-in / MPEG-4 Part 2(`mpeg4`) 로
///     정규화. 텍스트 카드 클립(무지출+영상없음)은 ffmpeg `color` lavfi 소스로 검은 배경 생성.
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

  // 864 = 16×54. HEVC/H.264 sw 인코더 모두 16-pixel 정렬된 폭에서 가장 안정적 — 854 같은 어정쩡한 값
  // 보다 한 줄 위로 맞춤.
  static const int _outWidth = 864;
  static const int _outHeight = 480;
  static const double _clipDurationSec = 2.0;
  static const double _xfadeDurationSec = 0.3;
  static const String _fontAssetPath = 'assets/fonts/Korean.ttf';
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
  Future<String> compose({
    required ExportPlan plan,
    required int challengeTargetAmount,
    required DateTime challengeStartDate,
    required String outputPath,
    required void Function(ComposeProgress progress) onPhase,
  }) async {
    _cancelled = false;

    if (plan.clips.isEmpty) {
      throw const VideoComposeFailed('합본에 포함된 클립이 없어요.');
    }

    // 1. 폰트 자산을 ffmpeg 가 읽을 수 있는 파일 경로로 복사 (assets bundle 은 네이티브에서 직접 못 읽음).
    final fontPath = await _materializeFontAsset();

    final tmpDir = await _ensureWorkDir(challengeStartDate);
    final normalizedPaths = <String>[];

    // 2. Pass 1 — 클립별 정규화.
    final dashboardTexts = _buildDashboardTexts(plan, challengeTargetAmount, challengeStartDate);
    for (var i = 0; i < plan.clips.length; i++) {
      _throwIfCancelled();
      onPhase(ComposeProgress(
        phase: ComposePhase.normalizing,
        currentIndex: i,
        totalCount: plan.clips.length,
        message: '클립 정규화 ${i + 1}/${plan.clips.length}',
      ));
      final clip = plan.clips[i];
      final outPath = '${tmpDir.path}/norm_$i.mp4';
      await _normalizeClip(
        clip: clip,
        dashboardText: dashboardTexts[i],
        fontPath: fontPath,
        outputPath: outPath,
      );
      normalizedPaths.add(outPath);
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

  Future<String> _materializeFontAsset() async {
    final tmp = await getTemporaryDirectory();
    final out = File('${tmp.path}/tenk_export/Korean.ttf');
    if (!await out.exists()) {
      // rootBundle.load 실패 (자산 누락) vs 파일 쓰기 실패 를 분리해서 메시지에 노출. 광범위 catch 가
      // 진짜 원인을 가리는 케이스를 봤음 — 자산 추가 후에도 "폰트 없어요" 가 떠 사용자 혼란.
      ByteData bytes;
      try {
        bytes = await rootBundle.load(_fontAssetPath);
      } catch (e) {
        throw MissingFontException(
            'rootBundle.load 실패 — pubspec.yaml 에 assets/fonts/ 등록됐는지, '
            '앱을 cold restart 했는지 확인. 원인: $e');
      }
      try {
        await out.parent.create(recursive: true);
        await out.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      } catch (e) {
        throw VideoComposeFailed('폰트를 임시 디렉토리에 복사 실패: $e');
      }
    }
    return out.path;
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
    required String fontPath,
    required String outputPath,
  }) async {
    final subtitle = _escapeDrawtext(clip.comment);
    final dashboard = _escapeDrawtext(dashboardText);
    final fontEsc = _escapePath(fontPath);

    final drawtextDashboard =
        "drawtext=fontfile='$fontEsc':text='$dashboard'"
        ':fontcolor=white:fontsize=28'
        ':x=(w-text_w)/2:y=24'
        ':box=1:boxcolor=black@0.55:boxborderw=10';
    final drawtextSubtitle =
        "drawtext=fontfile='$fontEsc':text='$subtitle'"
        ':fontcolor=white:fontsize=32'
        ':x=(w-text_w)/2:y=h-text_h-32'
        ':box=1:boxcolor=black@0.55:boxborderw=10';

    final localPath = clip.localVideoPath;
    final List<String> cmd;
    if (localPath != null) {
      // 영상 클립: scale+pad → SAR 정리 → drawtext → 인코더 픽셀 포맷 정합.
      final inEsc = _escapePath(localPath);
      final outEsc = _escapePath(outputPath);
      final filter = 'scale=$_outWidth:$_outHeight:force_original_aspect_ratio=decrease,'
          'pad=$_outWidth:$_outHeight:(ow-iw)/2:(oh-ih)/2:black,'
          'setsar=1,'
          '$drawtextDashboard,'
          '$drawtextSubtitle,'
          'format=$_outPixFmt';
      cmd = [
        '-y',
        '-i', inEsc,
        '-t', _clipDurationSec.toString(),
        '-vf', filter,
        '-an',
        '-c:v', _videoEncoder,
        '-b:v', _videoBitrate,
        '-r', '30',
        outEsc,
      ];
    } else {
      // 텍스트 카드: lavfi color 소스 + drawtext. 회의 결정 #8 (무지출+영상없음 → 2초 텍스트 카드).
      final outEsc = _escapePath(outputPath);
      cmd = [
        '-y',
        '-f', 'lavfi',
        '-i', 'color=c=black:s=${_outWidth}x$_outHeight:d=$_clipDurationSec:r=30',
        '-vf', '$drawtextDashboard,$drawtextSubtitle,format=$_outPixFmt',
        '-an',
        '-c:v', _videoEncoder,
        '-b:v', _videoBitrate,
        outEsc,
      ];
    }

    await _runFfmpeg(cmd);
  }

  Future<void> _concatWithXfade({
    required List<String> inputs,
    required String outputPath,
  }) async {
    // xfade 체이닝: 각 transition 의 offset 은 누적 (앞 클립 끝나기 0.3초 전부터).
    // 각 정규화 클립이 정확히 2초라고 가정 — `-t 2.0` 으로 클리핑했음.
    final overlap = _xfadeDurationSec;
    final clipLen = _clipDurationSec;

    final args = <String>['-y'];
    for (final p in inputs) {
      args.addAll(['-i', _escapePath(p)]);
    }

    final buf = StringBuffer();
    String prev = '[0:v]';
    for (var i = 1; i < inputs.length; i++) {
      final next = '[$i:v]';
      // 마지막 xfade 출력도 일단 중간 라벨로 받고, 뒤에서 format= 으로 통일해 [outv] 로 보낸다.
      final xfadeOut = '[x$i]';
      final offset = (clipLen - overlap) + (i - 1) * (clipLen - overlap);
      buf.write(
          '$prev${next}xfade=transition=fade:duration=$overlap:offset=${offset.toStringAsFixed(2)}$xfadeOut;');
      prev = xfadeOut;
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
      final trimmed = log.length > 800 ? '${log.substring(log.length - 800)}…' : log;
      throw VideoComposeFailed('ffmpeg 실패 (code=${code?.getValue()}). 로그 끝부분:\n$trimmed');
    }
  }

  /// drawtext text 값에 들어가는 문자열 이스케이프. ffmpeg drawtext 는 `:`, `'`, `\`, `%` 가 메타.
  static String _escapeDrawtext(String input) {
    return input
        .replaceAll('\\', '\\\\\\\\')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'")
        .replaceAll('%', '\\%');
  }

  /// Windows 백슬래시 경로를 ffmpeg drawtext 가 받아먹는 형태로 — 일단 그대로 통과
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

/// 한글 폰트 자산이 없을 때. `tenk_app/assets/fonts/Korean.ttf` 가 필요.
/// [detail] 은 디버그용 컨텍스트 (rootBundle.load 의 실제 에러 메시지 등). UI 에는 상위 레이어가
/// 더 친화적인 메시지로 감싸 보여준다.
class MissingFontException implements Exception {
  const MissingFontException([this.detail]);
  final String? detail;
  @override
  String toString() => detail == null
      ? 'MissingFontException: assets/fonts/Korean.ttf 가 없어요. README 참고.'
      : 'MissingFontException: $detail';
}
