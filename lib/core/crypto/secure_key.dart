import 'dart:typed_data';

/// A symmetric key held in memory. Backing bytes must be zeroable so derived
/// keys can be wiped on lock (zero-knowledge: no plaintext key persists).
abstract interface class SecureKey {
  int get length;

  /// Borrow the raw bytes for a crypto operation. Implementations may return a
  /// view; callers must not retain it past the call.
  Uint8List bytes();

  /// Overwrite the backing storage with zeros. Idempotent.
  void destroy();
}

/// Heap-backed key. A platform may substitute an mlock'd / enclave-backed key.
final class HeapSecureKey implements SecureKey {
  HeapSecureKey(Uint8List material)
      : _bytes = Uint8List.fromList(material);

  final Uint8List _bytes;
  bool _destroyed = false;

  @override
  int get length => _bytes.length;

  @override
  Uint8List bytes() {
    if (_destroyed) {
      throw StateError('SecureKey used after destroy');
    }
    return _bytes;
  }

  @override
  void destroy() {
    _bytes.fillRange(0, _bytes.length, 0);
    _destroyed = true;
  }
}
