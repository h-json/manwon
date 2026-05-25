import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../data/api/api_error.dart';

/// 2초 영상 촬영 전용 화면. 결과 path 를 [Navigator.pop] 으로 돌려준다 (취소 시 null).
///
/// 사양 (CLAUDE.md "영상" 정책):
/// - [ResolutionPreset.low] + 2초 타이머 (후처리 트랜스코딩 없음)
/// - `enableAudio=false` (RECORD_AUDIO 프롬프트 회피)
///
/// "사용" 을 안 누른 채로 닫혀도 자기가 찍은 임시 파일은 [dispose] 단계에서 정리한다.
/// 호출자는 반환된 path 만 관리하면 된다.
class AmountCameraScreen extends StatefulWidget {
  const AmountCameraScreen({super.key});

  @override
  State<AmountCameraScreen> createState() => _AmountCameraScreenState();
}

class _AmountCameraScreenState extends State<AmountCameraScreen>
    with SingleTickerProviderStateMixin {
  static const _recordDuration = Duration(seconds: 2);

  CameraController? _camera;
  Object? _cameraError;
  bool _initializing = true;
  bool _recording = false;
  Timer? _stopTimer;
  String? _recordedPath;
  bool _accepted = false;
  VideoPlayerController? _player;
  Object? _playerError;
  late final AnimationController _progressController;

  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;
  double _baseZoom = 1;
  Offset? _focusIndicator;
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _recordDuration,
    );
    _initCamera();
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _focusTimer?.cancel();
    _progressController.dispose();
    _camera?.dispose();
    _disposePlayer();
    // "사용" 안 누른 채 종료된 임시 파일 정리. 호출자에게 넘긴 경우(_accepted)는 호출자 책임.
    if (!_accepted) _deleteRecorded();
    super.dispose();
  }

  void _deleteRecorded() {
    final path = _recordedPath;
    if (path == null) return;
    File(path).delete().catchError((_) => File(path));
    _recordedPath = null;
  }

  void _disposePlayer() {
    final p = _player;
    if (p == null) return;
    p.removeListener(_onPlayerChanged);
    p.dispose();
    _player = null;
    _playerError = null;
  }

  Future<void> _initPlayer(String path) async {
    try {
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.play();
      controller.addListener(_onPlayerChanged);
      setState(() => _player = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _playerError = e);
    }
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _togglePlay() async {
    final c = _player;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          throw CameraException('no_camera', '사용 가능한 카메라를 찾지 못했어요.');
        }
        _cameras = cameras;
      }
      final controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final minZ = await controller.getMinZoomLevel();
      final maxZ = await controller.getMaxZoomLevel();
      // 일부 카메라(전면 등)는 플래시 미지원 — 실패해도 카메라 자체는 사용 가능.
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}
      setState(() {
        _camera = controller;
        _initializing = false;
        _minZoom = minZ;
        _maxZoom = maxZ;
        _currentZoom = 1;
        _baseZoom = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e;
        _initializing = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_recording || _cameras.length < 2) return;
    final current = _cameras[_cameraIndex].lensDirection;
    int nextIdx = (_cameraIndex + 1) % _cameras.length;
    for (var i = 0; i < _cameras.length; i++) {
      final idx = (_cameraIndex + 1 + i) % _cameras.length;
      if (_cameras[idx].lensDirection != current) {
        nextIdx = idx;
        break;
      }
    }
    final old = _camera;
    setState(() {
      _camera = null;
      _initializing = true;
      _cameraIndex = nextIdx;
      _flashMode = FlashMode.off; // 새 카메라(특히 전면) 기준으로 초기화
      _focusIndicator = null;
    });
    _focusTimer?.cancel();
    await old?.dispose();
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    final c = _camera;
    if (c == null || _recording) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await c.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flashMode = next);
    } catch (e) {
      if (!mounted) return;
      _showError('플래시 전환 실패: ${toApiException(e).message}');
    }
  }

  Future<void> _onTapFocus(Offset normalized, Offset local) async {
    final c = _camera;
    if (c == null || _recording) return;
    setState(() => _focusIndicator = local);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusIndicator = null);
    });
    // 일부 카메라/디바이스는 미지원 — 조용히 무시 (인디케이터만 노출).
    try {
      await c.setExposurePoint(normalized);
    } catch (_) {}
    try {
      await c.setFocusPoint(normalized);
    } catch (_) {}
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final c = _camera;
    if (c == null || _recording) return;
    if (details.pointerCount < 2) return; // 1손가락 팬은 탭 초점 영역 — 무시
    final next = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((next - _currentZoom).abs() < 0.01) return;
    setState(() => _currentZoom = next);
    try {
      await c.setZoomLevel(next);
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    final camera = _camera;
    if (camera == null || _recording) return;
    setState(() {
      _recording = true;
      _recordedPath = null;
    });
    try {
      await camera.startVideoRecording();
      _progressController.forward(from: 0);
      _stopTimer = Timer(_recordDuration, _stopRecording);
    } catch (e) {
      if (!mounted) return;
      _progressController.stop();
      _progressController.value = 0;
      setState(() => _recording = false);
      _showError('녹화 시작 실패: ${toApiException(e).message}');
    }
  }

  Future<void> _stopRecording() async {
    final camera = _camera;
    if (camera == null || !_recording) return;
    _stopTimer?.cancel();
    _stopTimer = null;
    try {
      final file = await camera.stopVideoRecording();
      if (!mounted) return;
      _progressController.value = 0;
      setState(() {
        _recording = false;
        _recordedPath = file.path;
      });
      await _initPlayer(file.path);
    } catch (e) {
      if (!mounted) return;
      _progressController.value = 0;
      setState(() => _recording = false);
      _showError('녹화 정지 실패: ${toApiException(e).message}');
    }
  }

  void _retake() {
    _disposePlayer();
    _deleteRecorded();
    setState(() {});
  }

  void _accept() {
    final path = _recordedPath;
    if (path == null) return;
    _accepted = true;
    Navigator.of(context).pop<String>(path);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('영상 촬영')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(child: _buildCameraArea(context)),
              const SizedBox(height: 16),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    final controller = _camera;
    if (_cameraError != null || controller == null) {
      final msg = _cameraError == null
          ? '카메라를 사용할 수 없어요.'
          : '카메라 초기화 실패: ${toApiException(_cameraError!).message}';
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _cameraError = null;
                });
                _initCamera();
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    if (_recordedPath != null) {
      return _buildRecordedPreview(theme);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _recording
                  ? null
                  : (details) {
                      final local = details.localPosition;
                      final normalized = Offset(
                        (local.dx / size.width).clamp(0.0, 1.0),
                        (local.dy / size.height).clamp(0.0, 1.0),
                      );
                      _onTapFocus(normalized, local);
                    },
              onScaleStart: _recording ? null : _onScaleStart,
              onScaleUpdate: _recording ? null : _onScaleUpdate,
              child: CameraPreview(controller),
            ),
            if (_focusIndicator != null)
              Positioned(
                left: _focusIndicator!.dx - 30,
                top: _focusIndicator!.dy - 30,
                child: IgnorePointer(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.yellow, width: 2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            Positioned(top: 8, right: 8, child: _buildTopControls()),
            if (_currentZoom > 1.05)
              Positioned(
                left: 8,
                bottom: 8,
                child: _buildZoomChip(_currentZoom),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTopControls() {
    if (_cameras.isEmpty) return const SizedBox.shrink();
    final isBack =
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;
    final canSwitch = !_recording && _cameras.length >= 2;
    final canFlash = !_recording && isBack && _camera != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isBack)
          _ControlButton(
            icon: _flashMode == FlashMode.torch
                ? Icons.flash_on
                : Icons.flash_off,
            enabled: canFlash,
            onPressed: _toggleFlash,
          ),
        if (_cameras.length >= 2) ...[
          const SizedBox(width: 8),
          _ControlButton(
            icon: Icons.flip_camera_ios,
            enabled: canSwitch,
            onPressed: _switchCamera,
          ),
        ],
      ],
    );
  }

  Widget _buildZoomChip(double zoom) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${zoom.toStringAsFixed(1)}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordedPreview(ThemeData theme) {
    if (_playerError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            const Text(
              '녹화 완료\n(미리보기를 불러올 수 없어요)',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final p = _player;
    if (p == null || !p.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: p.value.size.width,
              height: p.value.size.height,
              child: VideoPlayer(p),
            ),
          ),
        ),
        if (!p.value.isPlaying)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 48,
                color: Colors.white,
                icon: const Icon(Icons.play_arrow),
                onPressed: _togglePlay,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_recordedPath != null) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _retake,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 촬영'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _accept,
              icon: const Icon(Icons.check),
              label: const Text('사용'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
        ],
      );
    }
    final canRecord = !_initializing && _cameraError == null && _camera != null && !_recording;
    return _RecordButton(
      enabled: canRecord,
      recording: _recording,
      progress: _progressController,
      onTap: _startRecording,
    );
  }
}

/// 카메라 앱 스타일 원형 녹화 버튼.
///
/// - 바깥: 회색 링 (border)
/// - 안쪽: 빨간 원 (녹화 중엔 둥근 사각형으로 morph)
/// - 녹화 중엔 링을 따라 primary 색 호(arc)가 2초간 채워짐
class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.enabled,
    required this.recording,
    required this.progress,
    required this.onTap,
  });

  final bool enabled;
  final bool recording;
  final Animation<double> progress;
  final VoidCallback onTap;

  static const double _outer = 84;
  static const double _ring = 72;
  static const double _innerIdle = 56;
  static const double _innerRecording = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = enabled || recording
        ? theme.colorScheme.onSurface
        : theme.disabledColor;
    final innerColor = enabled || recording ? Colors.red : theme.disabledColor;
    return Semantics(
      button: true,
      enabled: enabled,
      label: recording ? '녹화 중' : '녹화 시작',
      child: SizedBox(
        width: _outer,
        height: _outer,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (recording)
              AnimatedBuilder(
                animation: progress,
                builder: (context, _) => CustomPaint(
                  size: const Size(_outer, _outer),
                  painter: _RecordProgressPainter(
                    progress: progress.value,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            GestureDetector(
              onTap: enabled ? onTap : null,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: _ring,
                height: _ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 3),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: recording ? _innerRecording : _innerIdle,
                    height: recording ? _innerRecording : _innerIdle,
                    decoration: BoxDecoration(
                      color: innerColor,
                      borderRadius: BorderRadius.circular(
                        recording ? 6 : _innerIdle / 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 프리뷰 위에 떠 있는 어두운 원형 아이콘 버튼 (플래시/셀카 전환).
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(icon, color: enabled ? Colors.white : Colors.white38),
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

class _RecordProgressPainter extends CustomPainter {
  const _RecordProgressPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    // 링(border 두께 3) 바깥쪽으로 호를 그리려고 deflate 로 살짝 안쪽에 잡음.
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(3);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(_RecordProgressPainter old) =>
      old.progress != progress || old.color != color;
}
