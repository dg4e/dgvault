// dgvault — SecureStore backed by the OS keystore (flutter_secure_storage).
//
// Production implementation of core's [SecureStore]: Keychain (iOS/macOS),
// Keystore/EncryptedSharedPreferences (Android), libsecret (Linux), DPAPI
// (Windows). Bytes are base64-wrapped because the plugin stores strings.
//
// PLATFORM-GATED: this runs only inside a real app on a supported OS. It cannot
// be unit-tested in the headless VM (the method channel has no host there →
// MissingPluginException). Core logic is tested against `InMemorySecureStore`;
// this adapter is exercised on-device / in integration tests.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/security/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FlutterSecureStorageStore implements SecureStore {
  FlutterSecureStorageStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> read(String key) async {
    final s = await _storage.read(key: key);
    return s == null ? null : Uint8List.fromList(base64.decode(s));
  }

  @override
  Future<void> write(String key, Uint8List value) =>
      _storage.write(key: key, value: base64.encode(value));

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> contains(String key) => _storage.containsKey(key: key);
}
