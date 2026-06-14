# dgvault — KeePass-Compatible Cross-Platform Password Manager

**Ensemble plan.** Tasks are claimed by changing `- [ ]` → `- [x] ... (Agent)` and committing
before work begins. Integration branch is `master`.

## Roles
- **🎼 Composer** — architecture, scaffolding, public interfaces, data models.
- **🎸 Performer** — implementation: business logic, tests, make it pass.
- **🔎 Critic** — review, test coverage, security audit, conformance to KeePass spec.

## Tech Stack (proposed — Composer to ratify Round 1)
- **Core:** Rust crate `dgcore` — KDBX4 parse/serialize, crypto (Argon2id, AES-256, ChaCha20),
  KeePass XML, field references, TOTP. Pure, deterministic, heavily unit-tested. Zero-knowledge:
  plaintext keys never leave the core; cleared on drop.
- **Bindings:** `flutter_rust_bridge` exposing `dgcore` to a **Flutter** UI (desktop + Android + iOS).
- **Secure storage:** platform keystore (Keychain/Keystore) via `flutter_secure_storage`;
  encrypted DB at rest is the KDBX file itself.
- **Rationale:** Rust core gives one audited crypto/format implementation across all platforms;
  Flutter gives one UI codebase. Native plugins bridge biometrics, autofill, SSH agent.

> If Composer chooses a different stack, this plan's task list stays valid — only the module
> names change. Acceptance criteria are stack-agnostic.

---

## Phase 0 — Foundation (Round 2 priority)
- [ ] Repo scaffold: workspace layout, `dgcore` crate, Flutter app shell, CI config — *Composer*
  - AC: `cargo test` and `flutter analyze` run green on empty scaffold.
- [ ] Core data model: `Database`, `Group`, `Entry`, `Field`, `Attachment`, `History`, `Tags` — *Composer*
  - AC: types serialize round-trip in tests; mirror KeePass XML schema fields.
- [ ] Error types + Result conventions across core — *Composer*
- [ ] Test harness + fixtures: sample KDBX4 files (empty, large, key-file, YubiKey) — *Critic*
  - AC: fixtures committed under `dgcore/fixtures/`; loader helper in tests.

## Phase 1 — Crypto & Format Core (Performer-heavy)
- [ ] Argon2id KDF (GPU-resistant) with configurable params — *Performer*
  - AC: matches KeePass reference vectors; param round-trips in header.
- [ ] AES-256-CBC + ChaCha20 cipher support — *Performer*
- [ ] KDBX4 header parse/serialize (incl. KDF params, cipher id, master seed) — *Performer*
- [ ] KeePass XML parse/serialize (groups, entries, history, times, tags) — *Performer*
  - AC: round-trip a KeePassXC-produced file byte-stable on re-export of unchanged data.
- [ ] Inner stream protection (ChaCha20 for protected fields) — *Performer*
- [ ] Composite key: master password + key file + challenge-response (YubiKey HMAC) — *Performer*
- [ ] KeePass field references & placeholders (`{REF:...}`, `{USERNAME}`, etc.) — *Performer*
- [ ] Conformance review of all Phase 1 against KDBX4 spec — *Critic*

## Phase 2 — Authentication & Unlock
- [ ] Master password unlock + Argon2 wiring — *Performer*
- [ ] PIN code unlock (PIN wraps a stored key blob in secure storage) — *Performer*
- [ ] Biometric unlock: Face ID / Touch ID / Android BiometricPrompt — *Performer*
- [ ] YubiKey support (challenge-response) + YubiKey Secret emergency unlock — *Performer*
- [ ] Duress PIN → open dummy database — *Performer*
- [ ] Duress PIN → delete all data — *Performer*
- [ ] App Lock: delete-all-on-N-fails counter — *Performer*
- [ ] Read-only mode flag (blocks all writes through one gate) — *Performer*
- [ ] Master password reminder scheduler — *Performer*
- [ ] Passkeys (WebAuthn) support — *Performer*
- [ ] Security review: duress flows, fail-counter, no key leakage — *Critic*

## Phase 3 — Database Features
- [ ] Local-only / local databases support — *Performer*
- [ ] Offline editing & viewing — *Performer*
- [ ] Large database handling (250MB+): streaming/lazy attachment load — *Performer*
- [ ] Rolling local backups (configurable retention) — *Performer*
- [ ] Compare databases (structural diff) — *Performer*
- [ ] Advanced sync & merge (KeePass merge by UUID + timestamps) — *Performer*
- [ ] Move items between databases — *Performer*
- [ ] Entry history (track/restore versions) — *Performer*

## Phase 4 — Password Generation & Entry Management
- [ ] Configurable + customizable password generator — *Performer*
- [ ] Diceware passphrase generator (bundled wordlist) — *Performer*
- [ ] Attachments & custom fields — *Performer*
- [ ] Custom icons + preset icon sets — *Performer*
- [ ] Custom order & sorting — *Performer*
- [ ] Tags (KeePass) — *Performer*
- [ ] Key file support (gen + use) — *Performer*
- [ ] Powerful search (all fields, including protected) — *Performer*
- [ ] Markdown notes rendering — *Performer*
- [ ] Custom URL handling — *Performer*

## Phase 5 — Sync, Import/Export, Integrations
- [ ] Import/Export 1Password + CSV (plain & encrypted) — *Performer*
- [ ] Direct URL import — *Performer*
- [ ] Local-network-only import/export — *Performer*
- [ ] Cloud sync: OneDrive, Google Drive, Dropbox (native) — *Performer*
- [ ] SFTP native — *Performer*
- [ ] WebDAV native (Nextcloud/Owncloud, SharePoint) — *Performer*
- [ ] iCloud + iOS Files integration — *Performer*

## Phase 6 — Utilities & Platform
- [ ] TOTP (RFC 6238, QR import, Steam) — *Performer*
- [ ] Favicon downloader — *Performer*
- [ ] Auto-clear clipboard (configurable timeout) — *Performer*
- [ ] Audit: weak/reused passwords (find weaknesses, find similar) — *Performer*
- [ ] AutoFill (Android Autofill Framework / iOS Credential Provider) — *Performer*
- [ ] SSH agent (desktop) — *Performer*
- [ ] Custom app icons — *Performer*

## Phase 7 — Hardening & Release
- [ ] Full test suite green on all platforms — *Critic*
- [ ] Security audit pass (zero-knowledge guarantees, memory zeroing) — *Critic*
- [ ] Docs: README, build, architecture, security model — *Composer*

---

## Round-by-round expectation
- **R1:** this plan (no business code). ✅
- **R2:** Phase 0 scaffold + start Phase 1 crypto/format core (the foundation everything needs).
- **R3+:** climb the phases; Critic reviews each phase before the ensemble votes consensus.

## Definition of Done (for CONSENSUS: YES)
All checkboxes checked, `cargo test` + `flutter test` green, Critic security review clean,
every feature in the task brief mapped to a completed task.
