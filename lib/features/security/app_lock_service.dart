import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Single place for app-lock state. The PIN is never stored: only a salted SHA-256 hash is kept in
/// encrypted device storage.
class AppLockService {
  AppLockService._();
  static const _storage = FlutterSecureStorage();
  static final _auth = LocalAuthentication();

  static const _enabledKey = 'ledgerlens_lock_enabled';
  static const _biometricKey = 'ledgerlens_biometric';
  static const _hashKey = 'ledgerlens_pin_hash';
  static const _saltKey = 'ledgerlens_pin_salt';
  static const _lengthKey = 'ledgerlens_pin_length';
  static const _legacyPinKey = 'ledgerlens_pin';

  static Future<bool> isEnabled() async => await _storage.read(key: _enabledKey) == 'true';
  static Future<bool> biometricEnabled() async => await _storage.read(key: _biometricKey) == 'true';
  static Future<bool> hasPin() async => (await _storage.read(key: _hashKey)) != null;

  /// The PIN length is not secret; it lets the lock screen verify exactly once per attempt.
  static Future<int> pinLength() async => int.tryParse(await _storage.read(key: _lengthKey) ?? '') ?? 4;

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _newSalt() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  static Future<void> setPin(String pin) async {
    final salt = _newSalt();
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: _hash(pin, salt));
    await _storage.write(key: _lengthKey, value: pin.length.toString());
    await _storage.delete(key: _legacyPinKey);
    await _storage.write(key: _enabledKey, value: 'true');
  }

  /// Upgrades a plain-text PIN written by v1.0 to a salted hash.
  static Future<void> migrateLegacyPin() async {
    final legacy = await _storage.read(key: _legacyPinKey);
    if (legacy != null && !await hasPin()) await setPin(legacy);
    if (legacy != null) await _storage.delete(key: _legacyPinKey);
  }

  static Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _saltKey);
    final hash = await _storage.read(key: _hashKey);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  static Future<bool> biometricsAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> enableBiometric() async {
    await _storage.write(key: _biometricKey, value: 'true');
    await _storage.write(key: _enabledKey, value: 'true');
  }

  static Future<void> disableBiometric() async {
    await _storage.delete(key: _biometricKey);
    if (!await hasPin()) await _storage.delete(key: _enabledKey);
  }

  static Future<void> removePin() async {
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _lengthKey);
    await _storage.delete(key: _legacyPinKey);
    if (!await biometricEnabled()) await _storage.delete(key: _enabledKey);
  }

  static Future<void> disableAll() async {
    for (final key in [_enabledKey, _biometricKey, _hashKey, _saltKey, _lengthKey, _legacyPinKey]) {
      await _storage.delete(key: key);
    }
  }
}
