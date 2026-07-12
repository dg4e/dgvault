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

  // ---- defensible ceilings (DoS hardening) --------------------------------
  //
  // A malicious .kdbx header can demand absurd KDF cost to exhaust memory / CPU
  // on open (Argon2 allocates `memoryKib` up front → multi-GiB OOM). Reject
  // anything above these ceilings BEFORE allocating. They sit far above any
  // legitimate interactive/paranoid setting, so real vaults are unaffected.

  /// Max Argon2 memory: 1 GiB (in KiB). Well above paranoid real-world configs.
  static const int maxMemoryKib = 1024 * 1024;

  /// Max Argon2 passes. KeePass benchmarks land in the low tens; 4096 is a very
  /// generous ceiling that still bounds per-open cost.
  static const int maxArgon2Iterations = 4096;

  /// Max AES-KDF transform rounds. Legitimate benchmarks reach a few million;
  /// this cap bounds a header that demands billions.
  static const int maxAesKdfIterations = 100000000;

  /// Max Argon2 lanes / parallelism. RFC 9106 allows up to 2^24 but no real
  /// vault needs more than this; a huge value is a red flag.
  static const int maxParallelism = 1024;

  /// Guards against malformed/under-strength AND hostile/over-strength headers
  /// before deriving a key. Enforces both minimums (correctness) and maximums
  /// (DoS hardening — a header must not be able to demand multi-GiB memory or
  /// pathological iteration counts that OOM / hang the app on open).
  bool get isValid {
    if (iterations < 1) return false;
    if (isArgon2) {
      final mem = memoryKib;
      final par = parallelism;
      if (mem == null || mem < 8 || mem > maxMemoryKib) return false;
      if (par == null || par < 1 || par > maxParallelism) return false;
      if (iterations > maxArgon2Iterations) return false;
    } else {
      if (iterations > maxAesKdfIterations) return false;
    }
    return true;
  }
}
