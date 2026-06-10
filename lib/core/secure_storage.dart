import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService._internal();
  static final SecureStorageService instance = SecureStorageService._internal();

  // flutter_secure_storage 10 dropped the EncryptedSharedPreferences-backed
  // Android implementation (Jetpack Security was deprecated by Google). The
  // plugin now uses custom ciphers by default and transparently migrates any
  // values written by earlier versions on first access, so Android needs no
  // options here.
  //
  // macOS: force the legacy file-based keychain instead of the default data
  // protection keychain (usesDataProtectionKeychain defaults to true). The data
  // protection keychain requires the keychain-access-groups / application-
  // identifier entitlement even when the app is unsandboxed, which an ad-hoc
  // signed build (no Apple Developer team) cannot satisfy — every write fails
  // with errSecMissingEntitlement (-34018). mOptions is macOS-only, so iOS and
  // Android behaviour is unchanged.
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const String _keyBaseUrl = 'slopcafe_base_url';
  static const String _keyOperatorToken = 'slopcafe_operator_token';

  static const String _keyUnboundOAuthClientIds =
      'slopcafe_unbound_oauth_client_ids';

  Future<void> saveConnectionDetails({
    required String baseUrl,
    required String operatorToken,
  }) async {
    // Normalise base URL (no trailing slash, check format)
    String formattedUrl = baseUrl.trim();
    if (formattedUrl.endsWith('/')) {
      formattedUrl = formattedUrl.substring(0, formattedUrl.length - 1);
    }

    await _storage.write(key: _keyBaseUrl, value: formattedUrl);
    await _storage.write(key: _keyOperatorToken, value: operatorToken.trim());
  }

  Future<String?> getBaseUrl() async {
    return await _storage.read(key: _keyBaseUrl);
  }

  Future<String?> getOperatorToken() async {
    return await _storage.read(key: _keyOperatorToken);
  }

  Future<List<String>> getUnboundOAuthClientIds() async {
    final raw = await _storage.read(key: _keyUnboundOAuthClientIds);
    if (raw == null || raw.isEmpty) return [];
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> addUnboundOAuthClientId(String clientId) async {
    final ids = await getUnboundOAuthClientIds();
    if (!ids.contains(clientId)) {
      ids.add(clientId);
      await _storage.write(
        key: _keyUnboundOAuthClientIds,
        value: ids.join(','),
      );
    }
  }

  Future<void> removeUnboundOAuthClientId(String clientId) async {
    final ids = await getUnboundOAuthClientIds();
    if (ids.contains(clientId)) {
      ids.remove(clientId);
      if (ids.isEmpty) {
        await _storage.delete(key: _keyUnboundOAuthClientIds);
      } else {
        await _storage.write(
          key: _keyUnboundOAuthClientIds,
          value: ids.join(','),
        );
      }
    }
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _keyBaseUrl);
    await _storage.delete(key: _keyOperatorToken);
    await _storage.delete(key: _keyUnboundOAuthClientIds);
  }
}
