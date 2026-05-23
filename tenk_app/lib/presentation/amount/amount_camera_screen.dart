import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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

class _AmountCameraScreenState extends State<AmountCameraScreen> {
  static const _recordDuration = Duration(seconds: 2);

  CameraController? _camera;
  Object? _cameraError;
  bool _initializing = true;
  bool _recording = false;
  Timer? _stopTimer;
  String? _recordedPath;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _camera?.dispose();
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

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', '사용 가능한 카메라를 찾지 못했어요.');
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e;
        _initializing = false;
      });
    }
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
      _stopTimer = Timer(_recordDuration, _stopRecording);
    } catch (e) {
      if (!mounted) return;
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
      setState(() {
        _recording = false;
        _recordedPath = file.path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recording = false);
      _showError('녹화 정지 실패: ${toApiException(e).message}');
    }
  }

  void _retake() {
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
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          const Text('2초 영상 녹화 완료'),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        if (_recording)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
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
    return FilledButton.icon(
      onPressed: canRecord ? _startRecording : null,
      icon: Icon(_recording ? Icons.fiber_manual_record : Icons.videocam),
      label: Text(_recording ? '녹화 중…' : '2초 녹화'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }
}
