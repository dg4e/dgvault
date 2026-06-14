/// Key-derivation-function parameters persisted in the KDBX header.
///
/// Argon2 is the default (GPU-resistant). AES-KDF is supported for reading
/// legacy databases. Parameter ranges follow KeePass / RFC 9106 guidance.
enum KdfAlgorithm {
  argon2d,
  argon2id,
  aesKdf,
}

class KdfParams {
  const KdfParams({
    required this.algorithm,
    required this.iterations,
    this.memoryKib,
    this.parallelism,
    this.version = 0x13,
  });

  /// Sensible interactive default: Argon2id, 64 MiB, 3 passes, 4 lanes.
  factory KdfParams.argon2idDefault() => const KdfParams(
        algorithm: KdfAlgorithm.argon2id,
        iterations: 3,
        memoryKib: 64 * 1024,
        parallelism: 4,
      );

  final KdfAlgorithm algorithm;

  /// Passes (Argon2) or transform rounds (AES-KDF).
  final int iterations;

  /// Memory cost in KiB (Argon2 only).
  final int? memoryKib;

  /// Lanes / threads (Argon2 only).
  final int? parallelism;

  /// Argon2 version (0x13 == v1.3).
  final int version;

  bool get isArgon2 =>
      algorithm == KdfAlgorithm.argon2d || algorithm == KdfAlgorithm.argon2id;

  /// Guards against malformed/under-strength headers before deriving a key.
  bool get isValid {
    if (iterations < 1) return false;
    if (isArgon2) {
      final mem = memoryKib;
      final par = parallelism;
      if (mem == null || mem < 8) return false;
      if (par == null || par < 1) return false;
    }
    return true;
  }
}
