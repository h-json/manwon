import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../data/api/api_error.dart';

/// 2초 영상 촬영 전용 화면. 결과 path 를 [Navigator.pop] 으로 돌려준다 (취소 시 null).
///
/// 사양 (CLAUDE.md "영상" 정책):
/// - [ResolutionPreset.medium] + 2초 타이머 (후처리 트랜스코딩 없음).
///   export 가 480x864 로 정규화하므로 medium 이상은 의미 없음.
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
    // progress + pulse 두 AnimationController 를 같이 들고 있어 Single 불가.
    with TickerProviderStateMixin {
  static const _recordDuration = Duration(seconds: 2);

  /// CameraX `startVideoRecording` 의 Future 가 실제 인코더 첫 프레임 쓰기 전에
  /// 먼저 resolve 되는 경우가 있어, future resolve 직후 바로 `_recordDuration`
  /// 타이머를 걸면 실제 캡처가 1초 정도로 잘려나가는 회귀가 있었다 (실측 기반).
  /// future resolve 후 이 만큼 추가로 기다린 뒤 게이지·타이머를 시작해 캡처 길이를
  /// 안정적으로 `_recordDuration` 에 맞춤. 이 동안 사용자는 "준비 중" spinner 를 본다.
  /// 트레이드오프: 탭한 순간은 캡처에 포함되지 않음 (캡처는 spinner 이후 2초).
  static const _encoderStartLag = Duration(milliseconds: 1000);

  CameraController? _camera;
  Object? _cameraError;
  bool _initializing = true;
  // 인코더/Muxer 워밍업 중 (init 직후 dummy start/stop). 워밍업 중엔 시작 버튼 잠금.
  bool _warmingUp = false;
  // startVideoRecording() 가 resolve 되기 전 (탭은 먹혔지만 아직 실제 녹화 시작 전).
  bool _starting = false;
  bool _recording = false;
  Timer? _stopTimer;
  String? _recordedPath;
  bool _accepted = false;
  VideoPlayerController? _player;
  Object? _playerError;
  late final AnimationController _progressController;
  /// 사용자가 녹화 버튼을 탭한 순간(`_starting`)부터 실제 녹화가 시작되는 순간
  /// (`_recording`) 사이를 잇는 단방향 morph driver. idle UI(큰 빨간 원) 가 recording
  /// UI(작은 둥근 사각형) 로 자연스럽게 변형되며, 마지막 ~15% 구간은 살짝 scale up
  /// 했다가 떨어지는 snap 으로 "시작 순간" 강조. duration 은 `_encoderStartLag` 보다
  /// 살짝 짧게 잡아 실제 녹화 시작 직전에 morph 가 도착해 있도록.
  late final AnimationController _startMorph;
  /// 녹화 시작 효과음 (`assets/sounds/record_start.mp3`) 전용 플레이어. 인스턴스를
  /// 들고 있어 매 호출 시 native player 를 새로 만들지 않게 한다.
  ///
  /// **PlayerMode 주의**: `lowLatency` 모드는 `setSource` 를 지원하지 않아 사전
  /// 로딩이 조용히 실패한다 (audioplayers 6.x 문서). 사전 로드 + `resume()` 패턴을
  /// 쓰려면 기본 MediaPlayer 모드를 유지할 것. 짧은 효과음이라도 latency 는 ~50ms
  /// 정도로 체감 안 됨.
  final AudioPlayer _startSound = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);

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
    _startMorph = AnimationController(
      vsync: this,
      // _encoderStartLag(1000ms) 보다 살짝 짧게 — startVideoRecording resolve 시간
      // 까지 합쳐도 실제 녹화 시작 시점엔 morph 가 완료돼 있도록.
      duration: const Duration(milliseconds: 850),
    );
    // 자산을 미리 로드해 둬서 실제 녹화 시작 순간엔 지연 없이 재생. 실패는 조용히
    // 무시 (사운드는 보조 시그널이고 햅틱 + 시각 효과로 충분).
    unawaited(_startSound.setSource(AssetSource('sounds/record_start.mp3')));
    _initCamera();
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _focusTimer?.cancel();
    _progressController.dispose();
    _startMorph.dispose();
    _startSound.dispose();
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
        ResolutionPreset.medium,
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
        _warmingUp = true;
        _minZoom = minZ;
        _maxZoom = maxZ;
        _currentZoom = 1;
        _baseZoom = 1;
      });
      // 인코더 워밍업은 init 와 별개로 진행. 실패해도 정상 흐름엔 영향 없음.
      unawaited(_warmupEncoder(controller));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e;
        _initializing = false;
      });
    }
  }

  /// MediaCodec/MediaMuxer 를 미리 한 번 할당해 첫 실제 녹화의 startVideoRecording
  /// 지연을 줄인다. camera 패키지의 prepareForVideoRecording 은 Android no-op 이라
  /// (audio prep 전용, iOS only) 직접 dummy 녹화로 워밍업.
  ///
  /// 짧은 녹화를 거부하는 기기가 있을 수 있어 실패는 조용히 무시. 컨트롤러가 그 사이
  /// 교체되거나(switchCamera) dispose 됐으면 결과를 반영하지 않는다.
  Future<void> _warmupEncoder(CameraController controller) async {
    String? path;
    try {
      await controller.startVideoRecording();
      await Future.delayed(const Duration(milliseconds: 150));
      final file = await controller.stopVideoRecording();
      path = file.path;
    } catch (_) {
      // 거부됐거나 컨트롤러가 사라짐 — 정상 흐름엔 영향 없음.
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted && _camera == controller) {
        setState(() => _warmingUp = false);
      }
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
    if (camera == null || _recording || _starting || _warmingUp) return;
    // _starting = 탭은 먹혔지만 startVideoRecording resolve 전. 버튼에 spinner 노출.
    // 게이지(progress arc) 는 실제 녹화가 시작된 _recording=true 시점부터만 돈다.
    setState(() {
      _starting = true;
      _recordedPath = null;
    });
    // 탭 즉시 청각 시그널 — "버튼 먹힘" 을 사용자에게 알리는 즉각 피드백. 햅틱·morph
    // snap 은 실제 녹화 시작 시점(recording=true)에 분리. 사유: 효과음을 녹화 시작
    // 시점에 두면 사용자 멘탈 모델로는 "녹화 중에 소리가 났다" 로 읽혀 어색
    // (enableAudio:false 라 영상 트랙엔 안 들어가지만 인지 모델이 그렇게 잡힘).
    unawaited(_playStartSound());
    // 탭 즉시 morph 시작 — idle 큰 원이 recording 작은 사각형으로 변형 시작.
    _startMorph.forward(from: 0);
    try {
      await camera.startVideoRecording();
      // CameraX 의 future resolve 가 실제 인코더 첫 프레임보다 빠른 경우를 보정.
      // 자세한 사유는 _encoderStartLag 주석 참고.
      await Future.delayed(_encoderStartLag);
      if (!mounted) return;
      // 녹화 시작 순간 촉각/시각 시그널. 효과음은 탭 즉시로 분리됨 (위 참고).
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _starting = false;
        _recording = true;
      });
      // morph 가 855ms 인데 wait 가 그보다 살짝 길어 거의 끝나 있을 것 — 안전하게 1로.
      _startMorph.value = 1;
      _progressController.forward(from: 0);
      _stopTimer = Timer(_recordDuration, _stopRecording);
    } catch (e) {
      if (!mounted) return;
      _progressController.stop();
      _progressController.value = 0;
      _startMorph.value = 0;
      setState(() {
        _starting = false;
        _recording = false;
      });
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
      _startMorph.value = 0;
      setState(() {
        _recording = false;
        _recordedPath = file.path;
      });
      await _initPlayer(file.path);
    } catch (e) {
      if (!mounted) return;
      _progressController.value = 0;
      _startMorph.value = 0;
      setState(() => _recording = false);
      _showError('녹화 정지 실패: ${toApiException(e).message}');
    }
  }

  void _retake() {
    _disposePlayer();
    _deleteRecorded();
    _startMorph.value = 0;
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

  /// 녹화 시작 효과음 1회 재생. 사전 로딩된 source 를 처음으로 되감고 resume.
  /// 사전 로드가 어떤 이유로 실패했다면 fallback 으로 그 자리에서 play 호출.
  /// 둘 다 실패해도 정상 흐름엔 영향 없게 catch 후 무시 — 사운드는 햅틱·시각의 보조.
  Future<void> _playStartSound() async {
    try {
      await _startSound.seek(Duration.zero);
      await _startSound.resume();
    } catch (_) {
      try {
        await _startSound.play(AssetSource('sounds/record_start.mp3'));
      } catch (_) {
        // 자산 로드 실패 / 시스템 음소거 — 햅틱과 시각 효과로 보완됨.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('영상 촬영')),
      body: SafeArea(
        top: false,
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
        // CameraPreview 를 그냥 Stack 자식으로 두면 StackFit.expand 가
        // 내부 AspectRatio 를 무시하고 강제로 늘려서 세로로 길어 보인다.
        // 녹화 후 미리보기(_buildRecordedPreview) 와 같은 cover-crop 패턴으로
        // 종횡비 유지 + 박스 채움. previewSize 는 센서(landscape) 기준이라
        // 포트레이트 표시용으로 width/height 를 swap.
        final preview = controller.value.previewSize;
        final previewW = preview?.height ?? 1.0;
        final previewH = preview?.width ?? 1.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewW,
                height: previewH,
                child: CameraPreview(controller),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // `_starting` 도 잠금: 녹화 직전 준비 구간엔 어떤 입력도 의미 없음
                // (탭 초점/줌 변경이 곧 시작될 녹화에 노이즈만 됨).
                onTapUp: (_recording || _starting)
                    ? null
                    : (details) {
                        final local = details.localPosition;
                        final normalized = Offset(
                          (local.dx / size.width).clamp(0.0, 1.0),
                          (local.dy / size.height).clamp(0.0, 1.0),
                        );
                        _onTapFocus(normalized, local);
                      },
                onScaleStart: (_recording || _starting) ? null : _onScaleStart,
                onScaleUpdate:
                    (_recording || _starting) ? null : _onScaleUpdate,
              ),
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
            if (!_recording && !_starting)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(child: _buildZoomPresets()),
              ),
          ],
        );
      },
    );
  }

  /// 디바이스 zoom 범위 기반 preset 목록. 항상 1x 포함.
  /// ultra-wide (minZoom < 0.95) 있으면 앞에, 2x / 5x 는 maxZoom 이 허용할 때만.
  List<double> _zoomPresets() {
    final list = <double>{1.0};
    if (_minZoom < 0.95) list.add(_minZoom);
    if (_maxZoom >= 2) list.add(2.0);
    if (_maxZoom >= 5) list.add(5.0);
    return list.toList()..sort();
  }

  Future<void> _setZoom(double zoom) async {
    final c = _camera;
    if (c == null || _recording) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    setState(() {
      _currentZoom = clamped;
      _baseZoom = clamped;
    });
    try {
      await c.setZoomLevel(clamped);
    } catch (_) {}
  }

  Widget _buildTopControls() {
    if (_cameras.isEmpty) return const SizedBox.shrink();
    final isBack =
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.back;
    final canSwitch = !_recording && !_starting && _cameras.length >= 2;
    final canFlash = !_recording && !_starting && isBack && _camera != null;
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

  /// 디바이스가 1x 만 지원하면 noop (preset 이 1개뿐이면 의미 없음).
  /// 현재 zoom 과 가까운(±0.15x) preset 1개를 active 로 강조. 핀치로 preset 사이
  /// 값으로 가면 어떤 것도 active 가 아니고, 그 실제 값을 라벨로 띄움.
  Widget _buildZoomPresets() {
    final presets = _zoomPresets();
    if (presets.length < 2) return const SizedBox.shrink();
    final activeIdx = presets.indexWhere(
      (z) => (_currentZoom - z).abs() < 0.15,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (activeIdx < 0)
          // preset 사이 — 실제 핀치 값 안내
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ZoomValueChip(value: _currentZoom),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < presets.length; i++)
                _ZoomPresetButton(
                  zoom: presets[i],
                  active: i == activeIdx,
                  onTap: () => _setZoom(presets[i]),
                ),
            ],
          ),
        ),
      ],
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
    final canRecord = !_initializing &&
        _cameraError == null &&
        _camera != null &&
        !_recording &&
        !_starting &&
        !_warmingUp;
    return _RecordButton(
      enabled: canRecord,
      recording: _recording,
      // morph 는 진짜 _starting (사용자 탭 후 대기) 동안만. 백그라운드 _warmingUp
      // 은 사용자 행동에 대한 응답이 아니므로 idle 그대로 (단지 disabled).
      starting: _starting && !_recording,
      progress: _progressController,
      startMorph: _startMorph,
      onTap: _startRecording,
    );
  }
}

/// 카메라 앱 스타일 원형 녹화 버튼. 세 상태 + 한 transition:
///
/// - **idle**: 회색 링 + 안쪽 큰 빨간 원 (size [_innerIdle])
/// - **starting (transition)**: 안쪽이 큰 원 → 작은 둥근 사각형으로 단방향 morph.
///   `startMorph` 0→1 동안 size 와 corner radius 가 부드럽게 변하고, 마지막 15%
///   구간엔 약한 anticipation+snap (scale 0.95 → 1.15 → 1.0) 으로 "지금 시작!" 강조.
/// - **recording**: 회색 링 + 작은 빨간 사각형 + primary 색 progress arc 가 2초간 채워짐.
///
/// idle 과 recording 의 시각 차이가 그대로 transition 의 시작/끝 상태가 되도록 설계 —
/// 대기 구간에 별도 효과음 같은 정지 애니메이션이 아니라 진짜 모양 변화로 잇는다.
class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.enabled,
    required this.recording,
    required this.starting,
    required this.progress,
    required this.startMorph,
    required this.onTap,
  });

  final bool enabled;
  final bool recording;
  /// "사용자가 탭해서 morph 가 진행 중" 인 경우. `_warmingUp` 은 포함 X — warmup
  /// 동안엔 그냥 disabled idle 로 보임.
  final bool starting;
  final Animation<double> progress;
  /// 0→1. starting=true 직후 forward, recording 으로 바뀌면 1 로 snap.
  final Animation<double> startMorph;
  final VoidCallback onTap;

  static const double _outer = 84;
  static const double _ring = 72;
  static const double _innerIdle = 56;
  static const double _innerRecording = 28;
  static const double _innerIdleRadius = _innerIdle / 2; // 완전 원
  static const double _innerRecordingRadius = 6; // 둥근 사각형

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = enabled || recording || starting
        ? theme.colorScheme.onSurface
        : theme.disabledColor;
    return Semantics(
      button: true,
      enabled: enabled,
      label: recording
          ? '녹화 중'
          : starting
              ? '준비 중'
              : '녹화 시작',
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
                child: Center(child: _buildInner(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInner(BuildContext context) {
    final theme = Theme.of(context);
    // morph 중이면 controller 로 그리고, 그 외엔 단순 AnimatedContainer 로 idle↔recording.
    if (starting) {
      return AnimatedBuilder(
        animation: startMorph,
        builder: (context, _) {
          final shape = _morphShape(startMorph.value);
          return Transform.scale(
            scale: shape.scale,
            child: Container(
              width: shape.size,
              height: shape.size,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(shape.radius),
              ),
            ),
          );
        },
      );
    }
    final innerColor = enabled || recording ? Colors.red : theme.disabledColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: recording ? _innerRecording : _innerIdle,
      height: recording ? _innerRecording : _innerIdle,
      decoration: BoxDecoration(
        color: innerColor,
        borderRadius: BorderRadius.circular(
          recording ? _innerRecordingRadius : _innerIdleRadius,
        ),
      ),
    );
  }

  /// startMorph 0..1 을 받아 그 시점의 (size, radius, scale) 을 반환. 세 구간:
  /// - 0..0.12: 살짝 작아짐 (scale 1.0 → 0.95) — anticipation. 모양은 큰 원 유지.
  /// - 0.12..0.85: 본 morph. size·radius 둘 다 easeInOut 으로 idle → recording.
  /// - 0.85..1.0: snap (scale 1.0 → 1.15 → 1.0 sine bump) — "지금 시작!" 순간 강조.
  ///   모양은 작은 둥근 사각형 정착 상태.
  static ({double size, double radius, double scale}) _morphShape(double t) {
    if (t < 0.12) {
      final local = t / 0.12;
      return (
        size: _innerIdle,
        radius: _innerIdleRadius,
        scale: 1.0 - local * 0.05,
      );
    }
    if (t < 0.85) {
      final local = (t - 0.12) / 0.73;
      final eased = Curves.easeInOutCubic.transform(local);
      return (
        size: _innerIdle + (_innerRecording - _innerIdle) * eased,
        radius: _innerIdleRadius +
            (_innerRecordingRadius - _innerIdleRadius) * eased,
        scale: 0.95 + 0.05 * eased,
      );
    }
    final local = (t - 0.85) / 0.15;
    // sin(pi * local) 은 0 → 1 → 0 호 — bump 모양.
    final bump = math.sin(local * math.pi) * 0.15;
    return (
      size: _innerRecording,
      radius: _innerRecordingRadius,
      scale: 1.0 + bump,
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

/// iOS 네이티브 카메라 스타일의 줌 preset 1개. active 면 흰 원 채움 + 진한 텍스트.
class _ZoomPresetButton extends StatelessWidget {
  const _ZoomPresetButton({
    required this.zoom,
    required this.active,
    required this.onTap,
  });

  final double zoom;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = zoom == zoom.roundToDouble()
        ? '${zoom.toInt()}x'
        : '${zoom.toStringAsFixed(1)}x';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontSize: active ? 13 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 핀치로 preset 사이 값에 멈춰 있을 때 실제 배율을 작게 띄우는 chip.
class _ZoomValueChip extends StatelessWidget {
  const _ZoomValueChip({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${value.toStringAsFixed(1)}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

