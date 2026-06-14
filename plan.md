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
- [x] KDBX4 reader/writer pipeline orchestrator (header ⇄ injected body-cipher ⇄ injected compressor ⇄ XML codec ⇄ model) — completes the format structure; real Argon2/AES body delegated via `KdbxBodyCipher` interface (Composer)
- [x] KeePass 2.x XML inner-format codec (model ⇄ XML, package:xml) — unblocks KDBX reader/writer & Critic golden round-trip (Composer); Critic adversarial round-trip audit added R11 (XML metachars, whitespace-under-pretty bug-probe, unicode+Protected) — APPROVE; flagged forward interop risk: real KeePass protected values are inner-stream-encrypted+base64, KDBX layer must apply/strip around this codec
- [x] KDBX4 outer header + VariantDictionary binary codec (magic/version/TLV fields, KdfParameters ⇄ KdfParams; SHA-256/HMAC framing + cipher/KDF transform remain, toolchain-gated) (Composer + Performer) — COLLISION RESOLVED R11 (Composer): both implemented independently; kept Composer's split form (`variant_dictionary.dart` + `kdbx_header.dart`) to avoid a duplicate `VariantDictionary` class; Performer's combined file superseded. Critic adversarial audit added R12 (VariantDictionary byte-stability for header HMAC, value edges, multibyte-key framing) — APPROVE; minor: Int32/Int64 are wire-decodable but lack typed get/set accessors
- [ ] Argon2 KDF (GPU-resistant) integration + params (Performer)
- [ ] AES-256 / ChaCha20 cipher layer (Performer)
- [ ] Encrypted local database storage at rest (Performer)
- [x] Key File support — key-file format parser (binary-32 / hex-64 / KeePass-2 XML / hashed-arbitrary → 32-byte key, injected SHA-256) feeding CompositeCredential (Composer); password→key hashing remains crypto-layer (Performer) — Critic R14 SECURITY SIGN-OFF (§4.5): APPROVE — detection order correct, v2 hash-mismatch rejects tampered files, injected SHA-256 (no hand-rolled crypto), length-validated; minor: `_bytesEqual` non-constant-time but acceptable (integrity hash of attacker-held file)
- [x] Entry History tracking — snapshot service + repository updateEntry wiring (Composer; Performer deferred duplicate)
- [x] KeePass Field References & Placeholders resolver (Composer; +{URL:} components by Performer)
- [x] Tags (KeePass) model + Custom Fields + Attachments — tag index/rename/remove + custom-field + attachment-pool services (Performer)
- [ ] Core model unit tests + round-trip golden tests vs reference kdbx (Critic) — placeholder-resolver + entry-history + XML-codec + VariantDictionary adversarial audits DONE; R13: full-pipeline end-to-end round-trip (rich db: nested groups/protected custom/history/unicode/metachars/whitespace) DONE with stub cipher; ONLY remaining = real Argon2/AES body + KeePassXC reference-fixture golden (toolchain-gated)
- [x] ✅ INTEGRATION (round 7): `ensemble/Critic` now merged into master each round; all Critic CI gate + adversarial suites + reviews are on master (Critic)

### Phase 2 — Authentication & Lock (Rounds 3–4)
- [ ] PIN code unlock (Performer)
- [ ] Biometric unlock (Face ID / Touch ID via platform channel) (Performer)
- [ ] YubiKey support incl. Secret Unlock (emergency) (Performer)
- [x] Duress PIN — open dummy database (Composer) — unified `DuressPolicy` routing (real/decoy/duress-wipe/none → outcome) with indistinguishability invariant — Critic R15 SECURITY SIGN-OFF (R5/§4.5): APPROVE; added exhaustive matrix audit (duress always-wipes in every config + signal always benign/never-real). Caveat for caller: the hidden wipe must not add observable latency vs a normal decoy open, and credential matching MUST be constant-time (delegated to crypto layer)
- [x] Duress PIN — delete all data (Composer) — same `DuressPolicy`: duress secret triggers wipe-then-(decoy|fail), observably identical to a normal unlock — Critic R15 SECURITY SIGN-OFF: APPROVE (covered by same matrix audit)
- [x] App Lock — delete-all-on-fails policy — persistent consecutive-failure counter + wipe trigger (Performer) — Critic R14 SECURITY SIGN-OFF (R5/§4.5): logic APPROVE + interrupted-wipe audit tests. F1+F2 FIXED R15 (Performer): `maxAttempts<=0` now throws `ArgumentError` (release-safe) + `isWipePending` getter added — Critic VERIFIED in source R15, REQUEST_CHANGES resolved ✅
- [x] Read-only mode — data-layer write-guard repository (Composer)
- [x] Master password reminder scheduler — pure due/snooze scheduler (interval since last verify, injectable clock) (Composer) — Critic R16 review: APPROVE (correct; author tests comprehensive incl. snooze-noop & clears-snooze — no redundant tests added per §8)
- [ ] Secure storage wrapping of keys via OS keystore (Performer)
- [ ] Auth/lock state-machine unit tests (Critic)

### Phase 3 — Password Gen & Utilities (Round 4)
- [x] Configurable + customizable password generator (Performer)
- [x] Diceware passphrase generator + wordlist (Performer) — RESOLVED R4: `diceware_wordlist.dart` ships a 264-word embedded list (pure Dart, no asset → keeps core platform-agnostic) + EFF/plain parsers + `DicewareGenerator.standard()`; full EFF list loads via `DicewareWordlist.parseEff`
- [x] TOTP support (RFC 6238/4226 HOTP, Steam variant, otpauth:// QR URI, base32) — injected HMAC keeps it pure/testable against RFC 4226 vectors (Composer); real HMAC-SHA1/256/512 impl = crypto-layer (Performer) — Critic R17 APPROVE: verified RFC 4226 truncation math by hand; Composer's vectors (Appendix-D 0–2, Steam exact, base32, otpauth) excellent; Critic added the independent §5.4 canonical example (872921, offset-10 path) + digit-slicing + exact-multiple base32
- [x] Auto-clear clipboard timer — generation-guarded clear scheduler (newer copy supersedes), injectable clock (Performer) — Critic R16 SECURITY review: APPROVE; added end-to-end supersession assertion (stale timer inert past its own clearAt). Caller caveat: platform layer should verify the clipboard still holds the secret before wiping (avoid clobbering externally-copied content). Note: timeout>0 is an assert but fails SAFE (over-eager clear, not data loss)
- [x] Favicon downloader — pure favicon-URL resolution (well-known candidates + <link rel=icon> HTML parse, size-ordered, relative→absolute); HTTP fetch is platform layer (Performer) — Critic R19 review: APPROVE (pure URL logic, no security boundary; Performer's tests suffice per §8). Note: the platform fetch layer should bound response size/redirects and not send credentials
- [x] Generator + TOTP unit tests (Steam + RFC test vectors) (Critic) — generator adversarial audit DONE R3; TOTP RFC-vector audit DONE R17 (independent §5.4 offset-10 vector + digit-slicing + base32 boundary). COMPLETE

### Phase 4 — Security & Audit (Round 4–5)
- [x] Audit: find weaknesses (weak/reused/old passwords) (Performer)
- [x] Find-similar audit (Performer)
- [ ] Passkeys support (Performer)
- [x] Audit engine unit tests — adversarial coverage beyond author tests (Critic)

### Phase 5 — Database & Sync (Round 5)
- [x] Compare databases / advanced merge (3-way) (Performer)
- [ ] Offline editing + offline viewing (Performer)
- [ ] Large database handling (250MB+) — streaming/lazy load (Performer)
- [x] Rolling local backups — retention/rotation policy (keepLast + maxAge + maxTotalCount) + next-name (Performer)
- [x] Move items between databases — cross-DB move service w/ binary-pool relink (Composer); copyEntry deep-clone source-corruption FIXED R9 (was Critic T1)
- [x] Local-only / local databases support — database registry + storage-location model + local-only sync guard (refuses remote targets) (Composer) — Critic R19 SECURITY review: APPROVE — invariant enforced at 3 layers (construct/relocate/SyncGuard), robust. 🟠 hardening: `register()` lets a local-only id be overwritten by a non-local-only descriptor (silently lifts the guarantee → becomes syncable); recommend register() reject downgrading an existing local-only id. Pinned in `database_registry_audit_test.dart` — 🟠 HARDENED R20 (Composer): register() now throws LocalOnlyViolation when re-registering an existing local-only id as non-local-only (upgrades + same-guarantee re-register still allowed); Critic audit assertion flipped to expect rejection
- [ ] Cloud sync: OneDrive, Google Drive, Dropbox, iCloud (Performer)
- [ ] SFTP / WebDAV / Nextcloud / SharePoint native sync (Performer)
- [x] Merge-conflict + backup-rotation unit tests (Critic) — merge + cross-DB transfer audits DONE (found copyEntry source-corruption + LWW data-loss); backup-rotation half blocked (rolling backups unbuilt). R9 (Performer): LWW data-loss M1 FIXED (merge snapshots overwritten target to history + unions source history) and comparator M2 FIXED (attachment diffs detected); copyEntry corruption (T1) FIXED R9 (Composer: deep-clone) — Critic verified in source R10; all R8 findings now resolved. R15: backup-rotation half DONE — adversarial audit (keepLast hard-floor/no-over-delete, maxAge/maxTotalCount, sortable names) — APPROVE; minor: nextBackupName second-granularity → same-second name collision (recommend sub-second/counter suffix). This Critic task now COMPLETE

### Phase 6 — Import / Export (Round 5–6)
- [x] Import/Export 1Password + CSV (Performer)
- [ ] Import/Export CSV encrypted (Performer)
- [x] Direct URL import + local-network-only import/export — URL validate/format-dispatch + local-network host classifier (loopback/RFC1918/link-local/ULA/mDNS) + local-only guard (Performer)
- [x] Import/export round-trip tests (Critic) — data-loss FIXED R8 (Performer): export now emits a Tags column + one column per custom field (union), lossless round-trip; Critic's pinning test updated to assert preservation

### Phase 7 — UI & Entry Management (Round 6)
- [x] Powerful search (all fields) — core search engine (Composer); Critic adversarial audit added R10 (protected name-vs-value, AND×protection) — APPROVE
- [x] Custom order & sorting — core sort + manual reorder service (Composer); Critic adversarial audit added (descending-stability, purity, moveBefore edges) — APPROVE
- [x] Custom icons + preset icon sets — custom-icon pool (add/dedupe/reference-scan/orphan-prune) + preset-icon validation (Performer)
- [x] Markdown notes — render-agnostic parser (headings/code-fence/blockquote/lists/paragraph + inline bold/italic/code/link/autolink), UI renders the AST (Performer) — Critic R18 review: AST parser APPROVE (no security boundary here). ⚠ Cross-cutting: the UI MUST run markdown link/autolink targets through the custom-URL open-policy (above) before opening — a `[x](javascript:…)` link must not auto-open
- [x] Custom URL handling — URL override precedence ({URL} embed) + placeholder resolution + scheme classification + safe-to-auto-open policy (Composer); custom app icons (platform/UI) remain (Performer) — Critic R18 SECURITY review: override/placeholder/policy logic APPROVE, but 🔴 REQUEST_CHANGES: block-list bypass — a scheme with an embedded ASCII control char (e.g. `java\t script:`) fails scheme parsing → falls to implicit-https → autoOpen, defeating the javascript/data block (browsers strip \t/\n and would execute). Fix: strip ASCII control/whitespace from the scheme before block-list match; default colon-bearing-but-invalid schemes to confirmFirst not https. Pinned in `custom_url_audit_test.dart` — 🔴 FIXED R19 (Composer): scheme is now sanitized (ASCII control/whitespace stripped) before block-list match; colon-bearing-but-invalid schemes default to confirmFirst, never implicit-https. Critic audit assertions flipped to expect blocked; awaiting Critic re-verify

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
