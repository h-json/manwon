import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/scopes.dart';
import '../../data/amount/amount.dart';
import '../../data/api/api_error.dart';
import '../../data/challenge/challenge.dart';
import '../challenge/_formatters.dart';
import 'amount_camera_screen.dart';
import 'amount_video_preview_screen.dart';
import 'widgets/video_attachment_section.dart';

/// 기록 수정 화면. 카드 탭으로 진입한다.
///
/// 수정 가능한 것:
/// - 지출: 카테고리/내용/금액/메모/**시간만** (날짜는 고정) + 영상 추가/교체/삭제
/// - 무지출: 메모 + 영상 추가/교체/삭제. 일시는 서버 now() 강제라 수정 불가.
///
/// 결과 (pop):
/// - `true`  → 수정 또는 삭제 완료 (호출자는 reload)
/// - `null`  → 취소
class AmountEditScreen extends StatefulWidget {
  const AmountEditScreen({
    super.key,
    required this.challenge,
    required this.original,
  });

  final Challenge challenge;
  final Amount original;

  @override
  State<AmountEditScreen> createState() => _AmountEditScreenState();
}

class _AmountEditScreenState extends State<AmountEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _categoryController;
  late final TextEditingController _contentController;
  late final TextEditingController _amountController;
  late final TextEditingController _memoController;

  late TimeOfDay _time;

  /// 영상 처리 액션. 진입 시 KEEP, 사용자가 손대면 REPLACE/REMOVE 로 전이.
  VideoAction _videoAction = VideoAction.keep;

  /// REPLACE 일 때만 non-null (새로 찍은 로컬 임시 파일).
  String? _newVideoPath;

  /// "영상 보기" 시 서버에서 받아온 로컬 캐시 경로. 한 번 받으면 화면 종료까지 재사용.
  String? _serverVideoLocalPath;
  bool _serverVideoLoading = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final o = widget.original;
    _categoryController = TextEditingController(text: o.category ?? '');
    _contentController = TextEditingController(text: o.content ?? '');
    _amountController = TextEditingController(
      text: o.noSpend ? '' : o.amount.toString(),
    );
    _memoController = TextEditingController(text: o.memo ?? '');
    _time = TimeOfDay.fromDateTime(o.spentDt);
  }

  @override
  void dispose() {
    _disposeLocalVideo();
    _disposeServerPreview();
    _categoryController.dispose();
    _contentController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _disposeLocalVideo() {
    final path = _newVideoPath;
    if (path == null) return;
    File(path).delete().catchError((_) => File(path));
    _newVideoPath = null;
  }

  void _disposeServerPreview() {
    final path = _serverVideoLocalPath;
    if (path == null) return;
    File(path).delete().catchError((_) => File(path));
    _serverVideoLocalPath = null;
  }

  Future<void> _loadServerVideo() async {
    if (_serverVideoLocalPath != null || _serverVideoLoading) return;
    final media = widget.original.mediaFiles.isEmpty
        ? null
        : widget.original.mediaFiles.first;
    if (media == null) return;
    final mediaApi = MediaScope.of(context);
    setState(() => _serverVideoLoading = true);
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/tenk_edit_preview');
      if (!await dir.exists()) await dir.create(recursive: true);
      // fileId 별 캐시 경로지만, 이전 호출의 잔재(짧은/깨진 파일)가 남아 있으면 truncate 가 늦거나
      // 다른 프로세스가 핸들을 잡고 있을 가능성을 차단하기 위해 항상 선삭제.
      final savePath = '${dir.path}/${media.fileId}.mp4';
      final saveFile = File(savePath);
      if (await saveFile.exists()) {
        try {
          await saveFile.delete();
        } catch (_) {
          // 삭제 실패는 무시 — dio 가 어차피 덮어쓴다. 검증은 사이즈로 한다.
        }
      }
      await mediaApi.downloadToFile(
        fileId: media.fileId,
        savePath: savePath,
      );
      // 0바이트 / 누락 방어 — 둘 다 video_player 초기화 실패로 이어진다. 캐시 안 박고 즉시 에러.
      if (!await saveFile.exists()) {
        throw StateError('다운로드된 파일이 존재하지 않아요 (fileId=${media.fileId})');
      }
      final size = await saveFile.length();
      if (size == 0) {
        throw StateError('다운로드된 파일이 비어 있어요 (fileId=${media.fileId})');
      }
      if (!mounted) return;
      setState(() => _serverVideoLocalPath = savePath);
    } catch (e) {
      if (!mounted) return;
      _showError('영상을 불러오지 못했어요: ${toApiException(e).message}');
    } finally {
      if (mounted) setState(() => _serverVideoLoading = false);
    }
  }

  /// "영상 보기" 진입: KEEP 이면 서버 영상을 lazy 다운로드 후, REPLACE 면 즉시
  /// [AmountVideoPreviewScreen] push. 미리보기에서 돌아온 액션(retake/delete)을 그대로 적용.
  Future<void> _onTapPreview() async {
    String? path;
    switch (_videoAction) {
      case VideoAction.replace:
        path = _newVideoPath;
      case VideoAction.keep:
        if (_serverVideoLocalPath == null) {
          await _loadServerVideo();
          if (!mounted) return;
        }
        path = _serverVideoLocalPath;
      case VideoAction.remove:
        return;
    }
    if (path == null) return;
    final result = await Navigator.of(context).push<VideoPreviewAction>(
      MaterialPageRoute<VideoPreviewAction>(
        builder: (_) => AmountVideoPreviewScreen(videoPath: path!),
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case VideoPreviewAction.retake:
        await _openCamera();
      case VideoPreviewAction.delete:
        _removeVideo();
    }
  }

  bool get _hasExistingServerVideo => widget.original.mediaFiles.isNotEmpty;

  bool get _hasAttachedVideo {
    switch (_videoAction) {
      case VideoAction.keep:
        return _hasExistingServerVideo;
      case VideoAction.replace:
        return _newVideoPath != null;
      case VideoAction.remove:
        return false;
    }
  }

  bool get _videoFromServer => _videoAction == VideoAction.keep && _hasExistingServerVideo;

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
  }

  Future<void> _openCamera() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const AmountCameraScreen()),
    );
    if (path == null || !mounted) return;
    _disposeLocalVideo();
    setState(() {
      _newVideoPath = path;
      _videoAction = VideoAction.replace;
    });
  }

  void _removeVideo() {
    _disposeLocalVideo();
    setState(() {
      // 기존 서버 영상이 있다면 REMOVE 로 마킹, 없다면 KEEP 로 되돌림 (아무 변경 없음).
      _videoAction = _hasExistingServerVideo ? VideoAction.remove : VideoAction.keep;
    });
  }

  Future<void> _save() async {
    if (!widget.original.noSpend && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final api = AmountScope.of(context);
      final memo = _memoController.text.trim();
      await api.update(
        challengeId: widget.challenge.id,
        amountId: widget.original.id,
        noSpend: widget.original.noSpend,
        category: widget.original.noSpend ? null : _categoryController.text.trim(),
        content: widget.original.noSpend ? null : _contentController.text.trim(),
        amount: widget.original.noSpend ? null : int.parse(_amountController.text),
        memo: memo.isEmpty ? null : memo,
        // 무지출은 백엔드가 time 무시. 지출만 시간 전달.
        hour: widget.original.noSpend ? null : _time.hour,
        minute: widget.original.noSpend ? null : _time.minute,
        videoAction: _videoAction,
        videoPath: _newVideoPath,
      );
      if (!mounted) return;
      _disposeLocalVideo();
      Navigator.of(context).pop<bool>(true);
    } catch (e) {
      if (!mounted) return;
      _showError('수정 실패: ${toApiException(e).message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('이 기록과 첨부된 영상이 삭제돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AmountScope.of(context).delete(
        challengeId: widget.challenge.id,
        amountId: widget.original.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop<bool>(true);
    } catch (e) {
      if (!mounted) return;
      _showError('삭제 실패: ${toApiException(e).message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noSpend = widget.original.noSpend;
    final title = noSpend ? '무지출 기록 수정' : '지출 기록 수정';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: AbsorbPointer(
          absorbing: _busy,
          child: Form(
            key: _formKey,
            child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!noSpend) ..._buildDateTimeSection(theme),
              if (!noSpend) ..._buildSpendFields(theme),
              Text('메모 (선택)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextFormField(
                controller: _memoController,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: noSpend
                      ? '예) 오늘 잘 참았다'
                      : '예) 회식이라 어쩔 수 없었음',
                ),
              ),
              const SizedBox(height: 24),
              Text('영상 (선택, 2초)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              VideoAttachmentSection(
                hasVideo: _hasAttachedVideo,
                fromServer: _videoFromServer,
                onPickNew: _openCamera,
                onRemove: _removeVideo,
                expandable: true,
                previewLoading: _serverVideoLoading,
                onTapPreview: _onTapPreview,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('저장'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _delete,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('삭제'),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDateTimeSection(ThemeData theme) {
    return [
      Text('일시', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '날짜 (변경 불가)',
                border: OutlineInputBorder(),
              ),
              child: Text(formatDate(widget.original.spentDt)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '시간',
                  border: OutlineInputBorder(),
                ),
                child: Text(_time.format(context)),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildSpendFields(ThemeData theme) {
    return [
      Text('카테고리', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      TextFormField(
        controller: _categoryController,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '예) 식비, 교통, 카페',
        ),
        validator: (raw) =>
            (raw == null || raw.trim().isEmpty) ? '카테고리를 입력해주세요.' : null,
      ),
      const SizedBox(height: 24),
      Text('내용', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      TextFormField(
        controller: _contentController,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '예) 김밥 한 줄',
        ),
        validator: (raw) =>
            (raw == null || raw.trim().isEmpty) ? '내용을 입력해주세요.' : null,
      ),
      const SizedBox(height: 24),
      Text('금액', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      TextFormField(
        controller: _amountController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          suffixText: '원',
        ),
        validator: (raw) {
          final v = int.tryParse(raw ?? '');
          if (v == null || v <= 0) return '1원 이상 숫자를 입력해주세요.';
          return null;
        },
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Builder(
        builder: (_) {
          final parsed = int.tryParse(_amountController.text);
          if (parsed == null) return const SizedBox.shrink();
          return Text(formatWon(parsed), style: theme.textTheme.bodySmall);
        },
      ),
      const SizedBox(height: 32),
    ];
  }
}
