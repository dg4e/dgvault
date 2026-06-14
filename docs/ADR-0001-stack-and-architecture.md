# ADR-0001 — Stack & Architecture

**Status:** Accepted (Round 1, reaffirmed Round 2)
**Authors:** Composer; approved by Performer (review round 1).

## Context
We must ship one KeePass-compatible password manager across desktop
(Linux/macOS/Windows), Android, and iOS, with heavy platform integration
(biometrics, AutoFill, SSH agent, cloud sync) and strict crypto correctness.

## Decision
- **Flutter (Dart)** single codebase. One UI + business layer; platform channels
  for OS-specific features.
- **KDBX 4.x** as the native database format, interoperable with KeePass 2.x XML.
- **Vetted crypto only** — Argon2 (KDF), AES-256 and ChaCha20 (cipher) via
  `cryptography` / `pointycastle` / kdbx. No hand-rolled primitives, ever.
- **Layered architecture** with a hard dependency rule:

  ```
  ui  ─▶ data ─▶ core
  platform ─▶ core
  ```

  `lib/core/` is pure Dart: no Flutter imports, no platform imports, no I/O.
  This keeps the entire domain model + crypto contracts unit-testable headless.

## Module contracts (Phase 0 deliverable)
- `core/model`: `Database`, `Group`, `Entry`, `Field`, `Attachment`,
  `KdfParams`, `ProtectedValue`.
- `core/crypto`: `SecureKey`, `KeyDerivation` (+ `CompositeCredential`),
  `Cipher` (+ `CipherRegistry`).

Performer implements concrete KDBX read/write, Argon2 KDF, and cipher impls
against these interfaces in Phase 1.

## Consequences
- + Maximal code sharing; testable core; clean seam for platform features.
- − Flutter desktop maturity varies; mitigated by isolating platform code.
- − Dart crypto perf for 250MB+ DBs; mitigated by streaming `Cipher` API and
  lazy attachment loading designed in from Phase 0.
