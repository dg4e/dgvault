# Critic Review — Round 19

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** local-only database guarantee (privacy/security boundary); favicon
resolver; status of the open R18 URL REQUEST_CHANGES.

## Local-only databases — SECURITY review: APPROVE (one hardening gap)
The "Local Only Databases" guarantee is enforced with good defense-in-depth — the
invariant (`localOnly ⇒ location must be local`) is checked at **three**
independent layers:
1. `DatabaseDescriptor` constructor throws `LocalOnlyViolation` on local-only +
   remote;
2. `relocate`/`withLocation` re-runs that check, so a local-only db can't be moved
   to a remote target (and the registry is left untouched on rejection);
3. `SyncGuard.ensureSyncAllowed` independently refuses any local-only db even if
   one somehow held a remote location, and refuses a purely-local db (no target).
Composer's tests cover all three thoroughly.

### 🟠 Hardening gap — `register()` allows a silent local-only downgrade
The flag is protected on *relocate* but not on *re-register*. `register()`
overwrites `_byId[id]` unconditionally, so re-registering an existing local-only
id with a descriptor whose `localOnly:false` + remote location succeeds (the
constructor doesn't object — the new descriptor is internally consistent) and the
once-local-only database becomes `syncable` and can sync OUT. A buggy import/restore
path or a mistaken UI action could thereby exfiltrate data the user marked
device-only. Pinned in `database_registry_audit_test.dart`.

Recommendation: `register()` (or a dedicated `update`) should refuse to replace an
existing local-only descriptor with one that is not local-only (or relocates it
remote) without an explicit, separate "disable local-only" action. Severity
medium-low (requires a same-id re-register), but it's exactly the invariant this
feature exists to hold.

## Favicon resolver — APPROVE
Pure favicon-URL resolution (well-known candidates, `<link rel=icon>` parse,
size-ordering, relative→absolute). No security boundary in the pure layer;
Performer's tests suffice (§8). Forward note for the platform fetch layer: bound
response size and redirect count, time out, and do not attach any
credentials/cookies when fetching a favicon for an arbitrary entry URL (SSRF /
data-exfil hygiene).

## Open from R18 — custom-URL control-char bypass STILL OPEN
Re-checked the source: `CustomUrlHandler` still only `trim()`s — no scheme
control-char stripping. The `java\tscript:` → implicit-https → autoOpen bypass
remains. REQUEST_CHANGES stands (Composer-owned). My pinned test still asserts the
current unsafe behaviour; I'll flip it once fixed.

## Status (§0)
~21 test files, ~17 Critic adversarial suites. Open: R18 URL REQUEST_CHANGES + the
R19 local-only register() hardening. The crypto body remains the toolchain-bound
core gate.

## Honesty note (§0)
Toolchain absent; the register() downgrade and the 3-layer invariant traced by
hand through the constructor / `withLocation` / `SyncGuard`.

## Consensus
NO. Open security REQUEST_CHANGES (custom-URL) + a local-only hardening gap; and
the crypto body still blocks encrypted-at-rest / zero-knowledge / KeePassXC golden
interop (§4.6). Phases 2 (platform auth), 6 (encrypted/URL export), 8 (platform)
largely unstarted.
