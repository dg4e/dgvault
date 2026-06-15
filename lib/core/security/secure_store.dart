// dgvault — secure key/blob storage abstraction (OS keystore).
//
// A thin async key→bytes store. The production implementation lives in the
// platform layer (Keychain / Keystore / libsecret / DPAPI via
// `flutter_secure_storage`); `lib/core` depends only on this interface so it
// stays platform-agnostic and unit-testable with the in-memory fake.

import 'dart:typed_data';

abstract interface class SecureStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List value);
  Future<void> delete(String key);
  Future<bool> contains(String key);
}

/// In-memory store for tests / sessions without OS persistence. NOT secure on
/// its own — production must back [SecureStore] with the OS keystore.
class InMemorySecureStore implements SecureStore {
  final Map<String, Uint8List> _data = {};

  @override
  Future<Uint8List?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Uint8List value) async =>
      _data[key] = Uint8List.fromList(value);

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<bool> contains(String key) async => _data.containsKey(key);
}
