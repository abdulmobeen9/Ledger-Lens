import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's own free Gemini key, kept in encrypted device storage (never uploaded, never in the build).
class AiKeyStore {
  AiKeyStore._();
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'ledgerlens_gemini_key';
  static const _modelName = 'ledgerlens_gemini_model';

  static Future<String?> key() => _storage.read(key: _keyName);
  static Future<String?> model() => _storage.read(key: _modelName);

  static Future<void> save(String key, String model) async {
    await _storage.write(key: _keyName, value: key);
    await _storage.write(key: _modelName, value: model);
  }

  static Future<void> saveModel(String model) => _storage.write(key: _modelName, value: model);

  static Future<void> clear() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _modelName);
  }
}
