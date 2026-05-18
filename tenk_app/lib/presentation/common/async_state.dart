import 'package:flutter/material.dart';

import '../../data/api/api_error.dart';
import 'error_view.dart';

/// `loading / data / error` 3-state + 세대 카운터를 캡슐화한 mixin.
///
/// 화면의 한 비동기 자원(예: 챌린지 목록, 챌린지 상세 1건)을 감싼다.
/// 한 화면이 두 종류 이상의 비동기 자원을 다뤄야 하면 mixin 대신 직접 state를 들 것.
///
/// 정책:
/// - 같은 화면에서 refresh를 빠르게 두 번 부르면 응답 순서가 뒤집힐 수 있다.
///   매 호출마다 [_loadGen]을 증가시켜 가장 최근 호출만 state에 반영.
/// - [load]가 끝나면 future를 그대로 반환하므로 `RefreshIndicator.onRefresh`에 바로 넘길 수 있다.
///   (단 에러가 떠도 인디케이터가 닫혀야 하므로 내부에서 삼킴.)
/// - FutureBuilder를 쓰지 않는 이유는 CLAUDE.md "코딩 컨벤션 — Flutter" 참고.
mixin AsyncStateMixin<W extends StatefulWidget, T> on State<W> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _loadGen = 0;

  T? get data => _data;
  Object? get error => _error;
  bool get loading => _loading;

  /// 자원 로더. 화면 단에서 실제 API 호출을 넘긴다.
  Future<T> fetch();

  /// `didChangeDependencies`에서 1회만 호출하면 첫 로드가 시작됨.
  /// 두 번째 이후 호출은 무시되므로 안전.
  void ensureLoaded() {
    if (_loadGen == 0) reload();
  }

  /// 재로딩. `RefreshIndicator.onRefresh`에 그대로 넘겨도 됨.
  Future<void> reload() async {
    final gen = ++_loadGen;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await fetch();
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// 외부 동작(예: finalize)으로 받은 새 값을 즉시 state에 반영.
  /// reload를 한 번 더 도는 것보다 가볍고 깜빡임이 없다.
  void replaceData(T next) {
    if (!mounted) return;
    setState(() {
      _data = next;
      _error = null;
      _loading = false;
    });
  }
}

/// [AsyncStateMixin] state를 일관된 로딩/에러/데이터 UI로 렌더.
///
/// - 최초 로딩(데이터 없음): 가운데 스피너
/// - 에러(데이터 없음): [ErrorView] + 재시도 버튼
/// - 데이터 있음: [builder]로 위임. 재로딩 중이어도 stale 데이터를 그대로 보여줌
///   (`RefreshIndicator`의 자체 인디케이터가 뜨므로 화면을 가리지 않는다).
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.data,
    required this.error,
    required this.loading,
    required this.onRetry,
    required this.builder,
  });

  final T? data;
  final Object? error;
  final bool loading;
  final Future<void> Function() onRetry;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    if (data != null) return builder(context, data as T);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return ErrorView(
        message: toApiException(error!).message,
        onRetry: onRetry,
      );
    }
    // ensureLoaded 전 한순간만 거치는 빈 상태.
    return const SizedBox.shrink();
  }
}
