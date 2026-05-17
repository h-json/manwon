import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_tokens.dart';

/// `flutter_secure_storage` 위에 얹은 단순 래퍼.
///
/// Android: EncryptedSharedPreferences, iOS: Keychain 으로 저장됨.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _kAccessToken = 'tenk.auth.accessToken';
  static const _kRefreshToken = 'tenk.auth.refreshToken';

  final FlutterSecureStorage _storage;

  Future<AuthTokens?> read() async {
    final at = await _storage.read(key: _kAccessToken);
    final rt = await _storage.read(key: _kRefreshToken);
    if (at == null || rt == null) return null;
    return AuthTokens(accessToken: at, refreshToken: rt);
  }

  Future<void> save(AuthTokens tokens) async {
    await _storage.write(key: _kAccessToken, value: tokens.accessToken);
    await _storage.write(key: _kRefreshToken, value: tokens.refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
  }
}
