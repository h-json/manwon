import 'package:flutter/material.dart';

/// 비동기 로딩 실패 시 보여주는 공용 에러 화면.
///
/// 화면 단위로 가운데 메시지 + "다시 시도" 버튼을 띄운다.
/// `RefreshIndicator` 안에서도 동작하도록 `AlwaysScrollableScrollPhysics`를 사용.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
