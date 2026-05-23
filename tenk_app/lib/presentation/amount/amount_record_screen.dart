import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scopes.dart';
import '../../data/amount/amount.dart';
import '../../data/api/api_error.dart';
import '../../data/challenge/challenge.dart';
import '../challenge/_formatters.dart';
import 'amount_camera_screen.dart';
import 'widgets/video_attachment_section.dart';

/// 지출/무지출 기록 추가 화면. 영상 첨부는 양쪽 모두 **선택** ([AmountCameraScreen] 으로 위임).
///
/// `noSpend = false`: 카테고리/내용/금액 입력 + 일시 (챌린지 기간 안)
/// `noSpend = true` : 메모만 입력 (일시는 서버 now() 강제)
class AmountRecordScreen extends StatefulWidget {
  const AmountRecordScreen({
    super.key,
    required this.challenge,
    required this.noSpend,
  });

  final Challenge challenge;
  final bool noSpend;

  @override
  State<AmountRecordScreen> createState() => _AmountRecordScreenState();
}

class _AmountRecordScreenState extends State<AmountRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final _contentController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  late DateTime _spentDt;
  String? _videoPath;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _spentDt = _defaultSpentDt();
  }

  /// 기본값: 지금. 날짜 부분이 챌린지 기간 밖이면 가장 가까운 챌린지 날짜로 옮기고 시각은 유지.
  DateTime _defaultSpentDt() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(widget.challenge.startDate)) {
      return _combine(widget.challenge.startDate, TimeOfDay.fromDateTime(now));
    }
    if (today.isAfter(widget.challenge.endDate)) {
      return _combine(widget.challenge.endDate, TimeOfDay.fromDateTime(now));
    }
    return now;
  }

  static DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  void dispose() {
    // 사용자가 촬영만 하고 저장 안 한 채 뒤로 가면 임시 파일 정리.
    _disposeLocalVideo();
    _categoryController.dispose();
    _contentController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _disposeLocalVideo() {
    final path = _videoPath;
    if (path == null) return;
    File(path).delete().catchError((_) => File(path));
    _videoPath = null;
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _spentDt,
      firstDate: widget.challenge.startDate,
      lastDate: widget.challenge.endDate,
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_spentDt),
    );
    if (pickedTime == null) return;
    setState(() {
      _spentDt = _combine(pickedDate, pickedTime);
    });
  }

  Future<void> _openCamera() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const AmountCameraScreen(),
      ),
    );
    if (path == null || !mounted) return;
    // 새 영상이 들어오면 이전 임시 파일은 폐기.
    _disposeLocalVideo();
    setState(() => _videoPath = path);
  }

  void _removeVideo() {
    _disposeLocalVideo();
    setState(() {});
  }

  Future<void> _submit() async {
    if (!widget.noSpend && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final api = AmountScope.of(context);
      final memo = _memoController.text.trim();
      // 무지출은 일시 입력 불가 — 백엔드가 서버 now() 로 강제하므로 명시적으로 null 을 보낸다.
      final result = await api.record(
        challengeId: widget.challenge.id,
        noSpend: widget.noSpend,
        dateTime: widget.noSpend ? null : _spentDt,
        category: widget.noSpend ? null : _categoryController.text.trim(),
        content: widget.noSpend ? null : _contentController.text.trim(),
        amount: widget.noSpend ? null : int.parse(_amountController.text),
        memo: memo.isEmpty ? null : memo,
        videoPath: _videoPath,
      );
      if (!mounted) return;
      // 업로드 성공 — 서버가 파일을 가져갔으니 로컬 임시 파일은 더 이상 필요 없음.
      // _disposeLocalVideo 가 _videoPath 를 null 로 만들기 때문에 pop 전에 호출하면 안전.
      _disposeLocalVideo();
      Navigator.of(context).pop<AmountRecordResult>(result);
    } catch (e) {
      if (!mounted) return;
      _showError('저장 실패: ${toApiException(e).message}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.noSpend ? '무지출 기록' : '지출 기록';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AbsorbPointer(
        absorbing: _submitting,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.noSpend) ...[
                Text('오늘 무지출', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '오늘 하루 지출이 없었다면 무지출로 기록할 수 있어요. 일시는 지금으로 자동 저장됩니다.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ] else ...[
                Text('일시', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _DateTimeField(
                  label: '기록 일시',
                  dt: _spentDt,
                  onTap: _pickDateTime,
                ),
                const SizedBox(height: 4),
                Text(
                  '챌린지 기간: ${formatPeriod(widget.challenge.startDate, widget.challenge.endDate)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
              if (!widget.noSpend) ..._buildSpendFields(theme),
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
                  hintText: widget.noSpend
                      ? '예) 오늘 잘 참았다'
                      : '예) 회식이라 어쩔 수 없었음',
                ),
              ),
              const SizedBox(height: 24),
              Text('영상 (선택, 2초)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              VideoAttachmentSection(
                hasVideo: _videoPath != null,
                fromServer: false,
                onPickNew: _openCamera,
                onRemove: _removeVideo,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
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

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.dt,
    required this.onTap,
  });

  final String label;
  final DateTime dt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(formatDateTime(dt)),
      ),
    );
  }
}
