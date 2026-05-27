import 'package:flutter/foundation.dart';

/// 백엔드 `UserResponse` 매핑. 결과 카드의 닉네임 표시 등에 사용.
@immutable
class User {
  const User({
    required this.userId,
    required this.email,
    required this.nickname,
  });

  final int userId;
  final String? email;
  final String? nickname;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: (json['userId'] as num).toInt(),
      email: json['email'] as String?,
      nickname: json['nickname'] as String?,
    );
  }
}
