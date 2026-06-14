# dgvault — Cross-Platform KeePass-Compatible Password Manager

**Plan author:** 🎼 Composer (technical architect)
**Round 1 status:** Scoring / planning only — no business code.

---

## 1. Architecture Decision Record (ADR)

### 1.1 Stack
- **Language / framework:** **Flutter (Dart)** for a single shared codebase across desktop (Linux/macOS/Windows), Android, and iOS.
  - Rationale: one UI + business-logic codebase, mature crypto FFI story, good platform-channel access for biometrics/AutoFill/SSH-agent, and a strong existing reference (`kdbx` Dart library) for KeePass `.kdbx` parsing.
- **KeePass core:** `kdbx` format (KDBX 4.x) with **Argon2** KDF and ChaCha20/AES-256 ciphers. XML inner format compatible with KeePass 2.x.
- **Crypto:** platform-vetted libs only — Argon2 + AES/ChaCha via `cryptography`/FFI; **no hand-rolled primitives.**
- **Secure storage:** OS keystore (Keychain / Keystore / libsecret / DPAPI) via `flutter_secure_storage` for wrapping keys; database file always encrypted at rest.
- **Architecture style:** layered — `core/` (pure Dart, platform-agnostic, fully unit-testable) ← `platform/` (channels) ← `ui/`. Zero-knowledge: master secret never persisted in plaintext; derived keys held only in memory and zeroed on lock.

### 1.2 Repo layout (target)
```
/lib
  /core        # kdbx model, crypto, KDF, merge, audit, generator (pure Dart)
  /platform    # biometrics, autofill, ssh-agent, cloud providers, secure storage
  /ui          # screens, widgets, state
  /data        # repositories, sync, backup, import/export
/test          # unit + golden tests mirroring lib/
/docs          # ADRs, format notes
```

### 1.3 Conventions
- Every `core/` module ships with unit tests; PRs without tests are REQUEST_CHANGES.
- Feature flags gate platform-specific features so the shared build stays green.
- `analysis_options.yaml` lint must pass; `flutter test` must be green before any CONSENSUS: YES.

---

## 2. Ownership Model

- **🎼 Composer** — architecture, interfaces/contracts, `core/` data model, scaffolding, plan upkeep.
- **🎻 Performer** — feature implementation against Composer's interfaces (UI, platform channels, sync).
- **🔎 Critic** — tests, audits, security review, acceptance verification.

Tasks tagged `(shared)` may be claimed by whoever pulls first per §2 claim protocol.

---

## 3. Phased Task Plan

### Phase 0 — Foundation (Round 2 target)
- [x] Scaffold Flutter project structure (`lib/core`, `lib/platform`, `lib/ui`, `lib/data`, `test/`) (Composer)
- [x] Add `analysis_options.yaml`, CI test script, and dependency manifest (`pubspec.yaml`) (Composer)
- [x] Define core domain interfaces: `Database`, `Entry`, `Group`, `Field`, `Attachment`, `KdfParams` (Composer)
- [x] Define crypto/KDF interface contracts (`Cipher`, `KeyDerivation`, `SecureKey`) (Composer)
- [x] Write ADR docs in `/docs` capturing stack + zero-knowledge model (Composer)
- [x] Establish CI quality gate (analyze + test) and golden round-trip test harness/strategy (Critic)

### Phase 1 — KeePass Core (Rounds 2–3)
- [ ] KDBX 4 reader/writer (XML inner format compatibility) (Performer)
- [x] KeePass 2.x XML inner-format codec (model ⇄ XML, package:xml) — unblocks KDBX reader/writer & Critic golden round-trip (Composer)
- [ ] Argon2 KDF (GPU-resistant) integration + params (Performer)
- [ ] AES-256 / ChaCha20 cipher layer (Performer)
- [ ] Encrypted local database storage at rest (Performer)
- [ ] Key File support + Master Password handling (Performer)
- [x] Entry History tracking — snapshot service + repository updateEntry wiring (Composer; Performer deferred duplicate)
- [x] KeePass Field References & Placeholders resolver (Composer; +{URL:} components by Performer)
- [x] Tags (KeePass) model + Custom Fields + Attachments — tag index/rename/remove + custom-field + attachment-pool services (Performer)
- [ ] Core model unit tests + round-trip golden tests vs reference kdbx (Critic) — placeholder-resolver + entry-history adversarial audits DONE; golden round-trip blocked on KDBX reader/writer
- [x] ✅ INTEGRATION (round 7): `ensemble/Critic` now merged into master each round; all Critic CI gate + adversarial suites + reviews are on master (Critic)

### Phase 2 — Authentication & Lock (Rounds 3–4)
- [ ] PIN code unlock (Performer)
- [ ] Biometric unlock (Face ID / Touch ID via platform channel) (Performer)
- [ ] YubiKey support incl. Secret Unlock (emergency) (Performer)
- [ ] Duress PIN — open dummy database (Performer)
- [ ] Duress PIN — delete all data (Performer)
- [ ] App Lock — delete-all-on-fails policy (Performer)
- [x] Read-only mode — data-layer write-guard repository (Composer)
- [ ] Master password reminder scheduler (Performer)
- [ ] Secure storage wrapping of keys via OS keystore (Performer)
- [ ] Auth/lock state-machine unit tests (Critic)

### Phase 3 — Password Gen & Utilities (Round 4)
- [x] Configurable + customizable password generator (Performer)
- [x] Diceware passphrase generator + wordlist (Performer) — RESOLVED R4: `diceware_wordlist.dart` ships a 264-word embedded list (pure Dart, no asset → keeps core platform-agnostic) + EFF/plain parsers + `DicewareGenerator.standard()`; full EFF list loads via `DicewareWordlist.parseEff`
- [ ] TOTP support (RFC 6238, QR import, Steam variant) (Performer)
- [ ] Auto-clear clipboard timer (Performer)
- [ ] Favicon downloader (Performer)
- [ ] Generator + TOTP unit tests (Steam + RFC test vectors) (Critic) — generator audit tests DONE; TOTP half blocked on impl

### Phase 4 — Security & Audit (Round 4–5)
- [x] Audit: find weaknesses (weak/reused/old passwords) (Performer)
- [x] Find-similar audit (Performer)
- [ ] Passkeys support (Performer)
- [x] Audit engine unit tests — adversarial coverage beyond author tests (Critic)

### Phase 5 — Database & Sync (Round 5)
- [x] Compare databases / advanced merge (3-way) (Performer)
- [ ] Offline editing + offline viewing (Performer)
- [ ] Large database handling (250MB+) — streaming/lazy load (Performer)
- [ ] Rolling local backups (Performer)
- [x] Move items between databases — cross-DB move service w/ binary-pool relink (Composer); copyEntry deep-clone source-corruption FIXED R9 (was Critic T1)
- [ ] Local-only / local databases support (Performer)
- [ ] Cloud sync: OneDrive, Google Drive, Dropbox, iCloud (Performer)
- [ ] SFTP / WebDAV / Nextcloud / SharePoint native sync (Performer)
- [x] Merge-conflict + backup-rotation unit tests (Critic) — merge + cross-DB transfer audits DONE (found copyEntry source-corruption + LWW data-loss); backup-rotation half blocked (rolling backups unbuilt). R9 (Performer): LWW data-loss M1 FIXED (merge snapshots overwritten target to history + unions source history) and comparator M2 FIXED (attachment diffs detected); copyEntry corruption (T1) is Composer-owned — still open

### Phase 6 — Import / Export (Round 5–6)
- [x] Import/Export 1Password + CSV (Performer)
- [ ] Import/Export CSV encrypted (Performer)
- [ ] Direct URL import + local-network-only import/export (Performer)
- [x] Import/export round-trip tests (Critic) — data-loss FIXED R8 (Performer): export now emits a Tags column + one column per custom field (union), lossless round-trip; Critic's pinning test updated to assert preservation

### Phase 7 — UI & Entry Management (Round 6)
- [x] Powerful search (all fields) — core search engine (Composer)
- [x] Custom order & sorting — core sort + manual reorder service (Composer); Critic adversarial audit added (descending-stability, purity, moveBefore edges) — APPROVE
- [ ] Custom icons + preset icon sets (Performer)
- [ ] Markdown notes rendering (Performer)
- [ ] Custom URL handling + custom app icons (Performer)

### Phase 8 — Platform Integrations (Round 6–7)
- [ ] AutoFill (Android/iOS) (Performer)
- [ ] iOS Files integration (Performer)
- [ ] SSH agent (desktop) (Performer)
- [ ] Platform integration smoke tests (Critic)

---

## 4. Acceptance Criteria (definition of done)

A feature is "done" when:
1. Its checkbox is checked with `(Owner)` annotation in plan.md.
2. Code lives under the correct `lib/` layer with a clear interface.
3. Corresponding unit tests exist and `flutter test` passes.
4. `flutter analyze` reports no errors.
5. For security-sensitive features (crypto, duress, secure storage): Critic has reviewed and approved in `reviews/`.
6. KeePass interop features validated against a reference `.kdbx` round-trip.

**Round 1 consensus criterion:** `plan.md` exists, is committed, and is merged to `main` with ownership + acceptance criteria defined. No business code expected this round.

---

## 5. Risk Register
- **R1 — Scope:** feature list is very large; phased delivery with hard "core-first" ordering mitigates. Crypto correctness gates everything.
- **R2 — Crypto correctness:** use vetted libs + test vectors only; Critic audits all crypto paths.
- **R3 — Platform fragmentation:** isolate behind `platform/` channel interfaces so `core/` stays testable headless.
- **R4 — Large DB performance:** design for streaming/lazy decryption from Phase 1, not retrofitted.
- **R5 — Duress safety:** delete-all paths must be irreversible-by-design yet guarded against accidental trigger; require Critic sign-off.
