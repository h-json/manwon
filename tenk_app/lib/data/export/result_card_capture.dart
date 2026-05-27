import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../amount/amount.dart';
import '../challenge/challenge.dart';
import '../../presentation/challenge/result_card/result_card_widget.dart';

/// [ResultCardWidget] 을 off-screen 으로 잠시 띄워 PNG 로 캡처하는 헬퍼.
///
/// 호출자는 두 가지 해상도를 골라 쓴다:
///  - 영상 export 마지막 카드용: [pixelRatio] = 1.0 → 480x864 (영상 export 해상도와 1:1)
///  - 갤러리/공유용: [pixelRatio] = 2.0 → 960x1728 (HiDPI 디바이스에서 깨끗하게)
///
/// **off-screen 위치 + RepaintBoundary** 패턴: Overlay 에 `Positioned(left: -2*width)` 로 화면 밖에
/// 잠깐 띄우고, RepaintBoundary 의 `toImage()` 로 layer 를 그대로 캡처. 위치는 시각적으로 안 보여도
/// layout/paint 는 정상 수행된다. 캡처 후 OverlayEntry 제거.
class ResultCardCapture {
  ResultCardCapture._();

  /// 결과 카드를 [outputPath] 에 PNG 로 저장한다. 파일이 이미 있으면 덮어쓴다.
  ///
  /// [context] 는 Overlay 와 ImageCache 를 찾을 수 있어야 한다 — 사용 가능한 화면에서 호출할 것.
  static Future<File> captureToFile({
    required BuildContext context,
    required Challenge challenge,
    required List<Amount> amounts,
    required String? nickname,
    required String outputPath,
    required double pixelRatio,
  }) async {
    final overlayState = Overlay.of(context, rootOverlay: true);
    final repaintKey = GlobalKey();

    // 1) 배지 아이콘 asset 들을 미리 캐시 — Image.asset 의 첫 프레임 미해상도 placeholder 캡처 방지.
    for (final b in challenge.badges) {
      try {
        await precacheImage(AssetImage(b.assetPath), context);
      } catch (_) {
        // errorBuilder 가 위젯에서 폴백 처리하므로 precache 실패해도 무해.
      }
    }
    if (!context.mounted) {
      throw StateError('context unmounted before capture');
    }

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -ResultCardWidget.width * 2,
        top: -ResultCardWidget.height * 2,
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: repaintKey,
            child: ResultCardWidget(
              challenge: challenge,
              amounts: amounts,
              nickname: nickname,
            ),
          ),
        ),
      ),
    );
    overlayState.insert(entry);

    try {
      // 두 프레임 대기 — 1st: 트리 빌드+레이아웃, 2nd: 페인트 안정화. Image.asset 은 위에서 precache 했음.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('RenderRepaintBoundary not attached');
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw StateError('결과 카드 PNG 변환 실패 (byteData null)');
        }
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
        return file;
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
  }
}
