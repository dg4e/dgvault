# dgvault — Cross-Platform KeePass-Compatible Password Manager

## Plan (Ensemble Round 1)

Integration branch: `master`. Agents: 🎼 Composer (architecture/scaffold), 🎹 Performer (implementation), 🎭 Critic (quality gate / review / tests).

---

## 0. Tech Stack Decision (Composer to finalize Round 2)

Proposed: **Flutter (Dart)** with a shared core package.
- Rationale: single codebase for desktop (Windows/macOS/Linux), Android, iOS; mature crypto FFI; `flutter_secure_storage` for OS keychains; good file/sync plugin ecosystem.
- KeePass core: pure-Dart KDBX4 parser/writer (Argon2 + ChaCha20/AES) in `packages/kdbx_core`.
- Alternative noted: Rust shared core + FFI if performance on 250MB+ DBs is insufficient. Decision criterion in §Acceptance.

- [ ] Confirm stack and scaffold repo structure (Composer)
- [ ] Define module boundaries: `kdbx_core`, `crypto`, `sync`, `ui`, `platform` (Composer)

---

## 1. Crypto & KDBX Core Foundation

- [ ] KDBX4 binary header parse/serialize (Composer)
- [ ] Argon2id KDF (GPU-resistant) with configurable params (Performer)
- [ ] AES-256 + ChaCha20 cipher support (Performer)
- [ ] KeePass XML inner format read/write (Performer)
- [ ] KeePass XML format compatibility round-trip with reference DB (Performer)
- [ ] Zero-knowledge architecture: keys never persisted in plaintext, memory zeroed after use (Performer)
- [ ] Encrypted local database storage at rest (Performer)
- [ ] Handle large databases (250MB+) — streaming/lazy attachment loading (Performer)

## 2. Authentication & Unlock

- [ ] Master password unlock (Performer)
- [ ] PIN code unlock (derived key wrap) (Performer)
- [ ] Face ID / Touch ID biometric unlock (Performer)
- [ ] Key file support (Performer)
- [ ] YubiKey support + YubiKey Secret emergency unlock (Performer)
- [ ] Duress PIN — open dummy database (Performer)
- [ ] Duress PIN — delete all data (Performer)
- [ ] App Lock — delete all on N failed attempts (Performer)
- [ ] Regular master password reminders (Performer)
- [ ] Read-only mode (Performer)
- [ ] Passkeys support (Performer)

## 3. Entry & Database Management

- [ ] Entries: title/user/pass/url/notes + custom fields + attachments (Performer)
- [ ] Custom icons + preset icon sets (Performer)
- [ ] Custom order & sorting (Performer)
- [ ] KeePass field references & placeholders (Performer)
- [ ] Tags (KeePass) (Performer)
- [ ] Entry history (Performer)
- [ ] Markdown notes rendering (Performer)
- [ ] Custom URL handling (Performer)
- [ ] Powerful search across all fields (Performer)
- [ ] Move items between databases (Performer)
- [ ] Compare databases / diff view (Performer)
- [ ] Local-only & local databases support (Performer)
- [ ] Rolling local backups (Performer)
- [ ] Offline editing & viewing (Performer)

## 4. Password Generation

- [ ] Configurable + customizable generator (length/charset/rules) (Performer)
- [ ] Diceware passphrase generator (Performer)

## 5. Security & Audit

- [ ] Audit: find weak/reused/breached passwords (Performer)
- [ ] Find similar audit (Performer)
- [ ] Auto-clear clipboard after timeout (Performer)
- [ ] TOTP support (QR import, RFC 6238, Steam) (Performer)

## 6. Sync, Import/Export

- [ ] Advanced sync & merge engine (3-way KDBX merge) (Performer)
- [ ] Cloud: OneDrive, Google Drive, Dropbox native sync (Performer)
- [ ] SFTP native (Performer)
- [ ] WebDAV native (covers Nextcloud/Owncloud) (Performer)
- [ ] SharePoint, iCloud (Performer)
- [ ] Import/Export 1Password + CSV (plain & encrypted) (Performer)
- [ ] Local network only import/export + Direct URL import (Performer)

## 7. Platform-Specific & Utilities

- [ ] iOS Files integration (Performer)
- [ ] AutoFill (Android/iOS) (Performer)
- [ ] SSH Agent (Desktop) (Performer)
- [ ] Favicon downloader (Performer)
- [ ] Custom app icons (Performer)

## 8. Quality Gate — owned by Critic

- [ ] Define acceptance criteria per module (Critic) — see below
- [ ] Test strategy: unit (crypto/kdbx), golden-file round-trip, widget, integration (Critic)
- [ ] CI lint + `flutter test` gate before any merge to master (Critic)
- [ ] Cross-review each Performer task; record in `reviews/Critic-round-N.md` (Critic)
- [ ] Security review: no plaintext key persistence, clipboard hygiene, duress paths (Critic)
- [ ] Verify KDBX interop against KeePassXC reference DBs (Critic)

---

## Acceptance Criteria (Critic)

A task is **APPROVED** only when:
1. **Correctness** — code does what the spec line says; no stubbed/fake logic claiming completion.
2. **Tests** — every core module (crypto, kdbx, generator, merge, audit) ships unit tests; round-trip golden tests for KDBX read/write; `flutter test` green.
3. **Spec compliance** — the corresponding `plan.md` checkbox maps to real, exercised code.
4. **Security** — zero-knowledge invariant holds: master key derived per-session, never written to disk in plaintext; PIN/biometric only unwrap an OS-keychain-stored DB key; duress and delete-on-fail paths are irreversible and tested.
5. **Interop** — DBs produced open in KeePassXC/KeePass2 and vice versa (golden reference files).
6. **Performance** — open/save of a 250MB DB completes without loading all attachments into memory at once (streaming verified).

Stack decision criterion: if pure-Dart KDBX cannot open a 250MB DB in < ~5s on mid-tier mobile, escalate to Rust FFI core.

## Complexity Estimates

- High: KDBX core, Argon2, sync/merge engine, AutoFill, YubiKey, large-DB streaming.
- Medium: auth flows, audit, TOTP, cloud providers, import/export.
- Low: password generator, tags, markdown, custom icons, clipboard clear.

## Ownership Summary

- **Composer**: stack, scaffold, module boundaries, KDBX header format.
- **Performer**: the bulk of feature implementation across §1–§7.
- **Critic**: acceptance criteria, test strategy, CI gate, cross-reviews, security/interop verification (§8).
