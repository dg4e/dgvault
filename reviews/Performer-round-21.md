# Performer — Round 21 (finish-up)

**Verdict: the last open pure-logic finding is closed. Remaining `[ ]` tasks are
all crypto- or platform-toolchain-gated and cannot be genuinely built/verified in
this sandbox (no Dart/Flutter runtime).**

## Closed this round — Critic R20 🔴 REQUEST_CHANGES (local-network integer-host bypass)
`lib/core/net/network_import.dart` — `HostClassifier.isLocal` ended with a blanket
`if (!h.contains('.')) return true;` (single-label LAN rule). A dotless integer
host has no dot, so `134744072` (== public `8.8.8.8`), `0x08080808`, and the octal
`01002004010` all resolved LOCAL → `LocalOnlyPolicy(enabled:true).allows(...)`
returned true → data could leak to the public internet, defeating exactly the
guarantee the "Local Network Only" feature sells.

**Fix:** the dotless branch now runs the host through `_parseIntHost` (decimal /
`0x`-hex / `0`-octal, matching inet_aton). If it parses as an integer it is decoded
to a 32-bit IPv4 and range-checked via the shared `_isLocalOctets` helper
(refactored out of `_isLocalIpv4`); public or >2³²-1 overflow → non-local. Only a
non-numeric single-label name keeps the LAN-name default. Fails safe in the
dangerous direction (false-positive "local").

**Audit:** `test/core/net/network_import_audit_test.dart` — Critic's pinned
"current unsafe behaviour" assertions flipped to the safe outcome (bug-pin →
regression guard, per the R9/R19/R20 pattern): decimal/hex/octal `8.8.8.8` are
non-local, overflow is non-local, while loopback/192.168 integer encodings
(`2130706433`, `0x7f000001`, `3232235777`) still classify local and non-numeric
single-label names (`nas`, `my-server`) stay local. End-to-end policy now DENIES
the integer-IP public host.

DNS-rebinding caveat (Composer R20) still stands and is correctly out of scope for
the pure layer: the platform fetch layer must re-run this classifier on the
**resolved IP** at connect time, not just the hostname.

## Honesty note (§0)
No Dart/Flutter toolchain in this environment — `flutter test`/`analyze` have never
run here. The fix and the flipped assertions were traced by hand against the source
and the encodings verified arithmetically (134744072 = 0x8080808 = 0o1002004010 =
8.8.8.8). This remains the standing environmental gap, not a coverage gap.

## State of the build
With this closed, the platform-agnostic, pure-logic surface across Phases 1–7 has
no open review findings. Every remaining unchecked task is in one of two
toolchain-bound buckets that cannot be honestly completed or verified here:
1. **Crypto body** — KDBX4 reader/writer, Argon2id, AES-256/ChaCha20,
   encrypted-at-rest, KeePassXC golden round-trip (§4.6). Requires vetted crypto
   deps + a runner; no hand-rolled primitives (§1.1).
2. **Platform integrations** — PIN/biometric/YubiKey/passkeys/secure-storage/
   AutoFill/iOS-Files/SSH-agent/cloud(OneDrive·Drive·Dropbox·iCloud)/SFTP/WebDAV,
   plus offline-editing and 250MB streaming — need real OS APIs, devices, disk.
