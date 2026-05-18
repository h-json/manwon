import 'package:flutter/foundation.dart';

enum ChallengeResult {
  success,
  fail;

  static ChallengeResult fromServer(String raw) {
    return switch (raw) {
      'SUCCESS' => ChallengeResult.success,
      'FAIL' => ChallengeResult.fail,
      _ => throw ArgumentError('Unknown ChallengeResult: $raw'),
    };
  }

  String get label => switch (this) {
        ChallengeResult.success => '성공',
        ChallengeResult.fail => '실패',
      };
}

@immutable
class Challenge {
  const Challenge({
    required this.id,
    required this.startDt,
    required this.endDt,
    required this.targetAmount,
    required this.totalSpent,
    required this.balance,
    required this.result,
    required this.finished,
  });

  final int id;
  final DateTime startDt;
  final DateTime endDt;
  final int targetAmount;
  final int totalSpent;
  final int balance;
  final ChallengeResult? result;
  final bool finished;

  bool get isInProgress => !finished && result == null;
  bool get awaitsFinalize => finished && result == null;

  factory Challenge.fromJson(Map<String, dynamic> json) {
    final resultRaw = json['result'] as String?;
    return Challenge(
      id: (json['challengeId'] as num).toInt(),
      startDt: DateTime.parse(json['startDt'] as String),
      endDt: DateTime.parse(json['endDt'] as String),
      targetAmount: (json['targetAmount'] as num).toInt(),
      totalSpent: (json['totalSpent'] as num).toInt(),
      balance: (json['balance'] as num).toInt(),
      result: resultRaw == null ? null : ChallengeResult.fromServer(resultRaw),
      finished: json['finished'] as bool,
    );
  }
}
