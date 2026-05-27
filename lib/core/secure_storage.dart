import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService._internal();
  static final SecureStorageService instance = SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const String _keyBaseUrl = 'slopcafe_base_url';
  static const String _keyOperatorToken = 'slopcafe_operator_token';

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

  Future<void> clearAll() async {
    await _storage.delete(key: _keyBaseUrl);
    await _storage.delete(key: _keyOperatorToken);
  }
}
