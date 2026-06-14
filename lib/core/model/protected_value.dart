/// A value that should be kept in memory-protected form (passwords, TOTP seeds,
/// custom secret fields). Backing bytes are intended to be zeroed on lock via
/// [dispose]; the in-memory representation is an interface so a platform can
/// supply an mlock'd / obfuscated buffer.
abstract interface class ProtectedValue {
  /// Whether this field is secret (UI masks it, audit treats it as a credential).
  bool get isProtected;

  /// Reveal the plaintext. Callers must not retain the result longer than needed.
  String reveal();

  /// Overwrite the backing storage. Idempotent.
  void dispose();
}

/// Default in-memory implementation. Stores plaintext as code units so the
/// backing list can be overwritten on [dispose]. Not a security boundary on its
/// own — platforms may override with mlock/secure-enclave backed buffers.
final class InMemoryProtectedValue implements ProtectedValue {
  InMemoryProtectedValue(String value, {this.isProtected = true})
      : _units = List<int>.of(value.codeUnits, growable: false);

  /// Convenience for clearly non-secret strings (titles, urls).
  factory InMemoryProtectedValue.plain(String value) =>
      InMemoryProtectedValue(value, isProtected: false);

  final List<int> _units;
  bool _disposed = false;

  @override
  final bool isProtected;

  @override
  String reveal() {
    if (_disposed) {
      throw StateError('ProtectedValue read after dispose');
    }
    return String.fromCharCodes(_units);
  }

  @override
  void dispose() {
    for (var i = 0; i < _units.length; i++) {
      _units[i] = 0;
    }
    _disposed = true;
  }
}
