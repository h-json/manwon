import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/scopes.dart';
import '../../../data/amount/amount.dart';
import '../../../data/challenge/challenge.dart';
import '../../../data/export/result_card_capture.dart';
import 'result_card_widget.dart';

/// 챌린지 결과 카드 풀스크린 화면. finalize 직후 자동 푸시 + 챌린지 상세의 진입 카드 양쪽에서 들어온다.
///
/// 화면에선 [FittedBox] 로 480x864 카드를 디바이스 비율에 맞춰 표시. 갤러리 저장/공유는 같은 카드를
/// [ResultCardCapture] 로 캡처해 PNG 로 저장. 같은 화면 안에서 두 번째 호출은 캐시 재사용.
class ResultCardScreen extends StatefulWidget {
  const ResultCardScreen({
    super.key,
    required this.challenge,
    required this.amounts,
  });

  final Challenge challenge;
  final List<Amount> amounts;

  @override
  State<ResultCardScreen> createState() => _ResultCardScreenState();
}

class _ResultCardScreenState extends State<ResultCardScreen> {
  /// 닉네임 fetch 완료 시 채워짐. fetch 전엔 null → 카드 헤더에 닉네임 없이 표시.
  String? _nickname;

  /// 저장/공유 시 await 하기 위한 future — fetch 가 늦으면 그때까지 기다린 뒤 캡처.
  Future<String?>? _nicknameFuture;

  /// 캡처된 PNG 파일 경로. 같은 세션 내 첫 호출 때만 캡처, 이후 재사용.
  String? _capturedPngPath;

  bool _saving = false;
  bool _sharing = false;
  bool _savedToGallery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchNickname());
  }

  Future<void> _fetchNickname() async {
    if (!mounted) return;
    final api = UserScope.of(context);
    final future = () async {
      try {
        final user = await api.getMe();
        return user.nickname;
      } catch (_) {
        // 닉네임이 못 와도 카드 표시/저장은 진행. 헤더만 "만원 챌린지" 로.
        return null;
      }
    }();
    _nicknameFuture = future;
    final value = await future;
    if (!mounted) return;
    setState(() => _nickname = value);
  }

  /// 캡처 PNG 를 만든다 (없으면). 동시 호출 시 같은 future 를 재사용하지 않고 있지만 _saving/_sharing
  /// guard 로 동시 트리거가 막혀 있어 race 우려 없음.
  Future<String> _ensureCaptured() async {
    if (_capturedPngPath != null) return _capturedPngPath!;
    // 닉네임 fetch 가 아직이면 잠깐 기다림 — 보통 즉시 끝남.
    if (_nicknameFuture != null && _nickname == null) {
      await _nicknameFuture;
    }
    if (!mounted) {
      throw StateError('Result card screen unmounted before capture');
    }
    final tmp = await getTemporaryDirectory();
    if (!mounted) {
      throw StateError('Result card screen unmounted before capture');
    }
    final path =
        '${tmp.path}/tenk_result_card/${widget.challenge.id}.png';
    await ResultCardCapture.captureToFile(
      context: context,
      challenge: widget.challenge,
      amounts: widget.amounts,
      nickname: _nickname,
      outputPath: path,
      pixelRatio: 2.0,
    );
    _capturedPngPath = path;
    return path;
  }

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final path = await _ensureCaptured();
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: false);
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('갤러리 접근 권한이 거부됐어요. 설정에서 사진 접근을 허용해주세요.'),
            ),
          );
          return;
        }
      }
      await Gal.putImage(path, album: 'Tenk');
      if (!mounted) return;
      setState(() => _savedToGallery = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('갤러리에 저장됐어요.')),
      );
    } on GalException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_galErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final path = await _ensureCaptured();
      final params = ShareParams(
        files: [XFile(path, mimeType: 'image/png')],
        text: '만원 챌린지 결과',
      );
      await SharePlus.instance.share(params);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static String _galErrorMessage(GalException e) {
    return switch (e.type) {
      GalExceptionType.accessDenied =>
        '갤러리 접근 권한이 거부됐어요. 설정에서 사진 접근을 허용해주세요.',
      GalExceptionType.notEnoughSpace => '저장 공간이 부족해요.',
      GalExceptionType.notSupportedFormat => '지원하지 않는 이미지 형식이에요.',
      GalExceptionType.unexpected => '알 수 없는 오류가 발생했어요.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E10),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('챌린지 결과'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: ResultCardWidget.width / ResultCardWidget.height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: ResultCardWidget(
                          challenge: widget.challenge,
                          amounts: widget.amounts,
                          nickname: _nickname,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _saving ? null : _saveToGallery,
                      icon: Icon(_savedToGallery
                          ? Icons.check
                          : Icons.download_outlined),
                      label: Text(
                        _saving
                            ? '저장 중…'
                            : _savedToGallery
                                ? '저장됨'
                                : '갤러리 저장',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : _share,
                      icon: const Icon(Icons.ios_share),
                      label: Text(_sharing ? '공유 중…' : '공유하기'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
