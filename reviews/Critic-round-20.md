# Critic Review — Round 20

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** verify R18 custom-URL fix; security review of the local-network host
classifier (direct URL import / local-network-only).

## ✅ R18 custom-URL control-char bypass — FIX VERIFIED, REQUEST_CHANGES CLOSED
Composer fixed it and flipped my pinned assertions; I re-verified both in source
(§0, not on trust):
- `_analyze` now computes `_sanitizeScheme(rawScheme)` = strip code units ≤ 0x20
  and 0x7f, then lowercase, and matches the **block-list on the sanitized scheme**
  — so `java\tscript`, `javascript\t`, `da\nta` all resolve to their real
  dangerous scheme and are **blocked**.
- A scheme token that fails the RFC grammar (`weird scheme`) now returns
  `confirmFirst` and **never falls through to implicit-https/autoOpen**.
- Legit cases still classify correctly (https/ssh autoOpen; cmd/file confirmFirst;
  `host:port` → implicit https). Traced by hand. My audit assertions are correct.

## Local-network host classifier — 🔴 REQUEST_CHANGES (SSRF/leak bypass)
The "Local Network Only" guard exists so a transfer can never reach the public
internet. Its only dangerous failure direction is a **false positive** (a public
host classified local). Dotted-IPv4, IPv6 (loopback/link-local/ULA), `.local`, and
public-FQDN cases are all handled correctly. But:

**Finding — dotless integer-encoded public IP is classified local.**
`isLocal` ends with `if (!h.contains('.')) return true;` (single-label LAN name).
A pure-integer host has no dots, so `134744072` — the decimal encoding of the
**public** `8.8.8.8` — returns `true`. End-to-end, `LocalOnlyPolicy(enabled:true)
.allows('http://134744072/')` returns **true**, so under "local network only" a
fetch/export to a public IP is permitted. HTTP stacks (curl and many libraries)
resolve all-integer hosts as IPv4, so this actually reaches 8.8.8.8. Same class:
`0x08080808` (hex) and `0xITHEXPUBLIC`. Pinned in `network_import_audit_test.dart`.

**Fix:** before the single-label rule, detect a host that is all-digits (or
`0x`/`0`-prefixed) and parse it as an integer IPv4 (32-bit), then range-check like
a dotted IP — or simply deny integer hosts under local-only. A real single-label
LAN name has at least one non-digit. Severity medium: it needs an integer-IP host
in the import URL, but it defeats exactly the guarantee this feature sells.

Note: `::ffff:<v4>` IPv4-mapped IPv6 is currently treated as non-local (denied) —
safe direction (over-deny), but worth normalizing later for usability.

## DirectImportUrl (scheme validate + format detect) — APPROVE
Scheme allow-list + content-type/extension format dispatch are straightforward and
covered by Performer's tests; no security concern in the pure layer.

## Status (§0)
~22 test files, ~18 Critic adversarial suites. R18 URL REQUEST_CHANGES now closed;
one new REQUEST_CHANGES (integer-host local-net bypass) + the R19 local-only
register() hardening remain open. Crypto body still the toolchain-bound core gate.

## Honesty note (§0)
Toolchain absent; the integer-IP bypass and the URL fix both traced by hand
through the source.

## Consensus
NO. New security REQUEST_CHANGES (local-network integer-host bypass); R19 register()
hardening open; and the crypto body still blocks encrypted-at-rest / zero-knowledge
/ KeePassXC golden interop (§4.6). Phases 2 (platform auth), 8 (platform) and
several sync providers unstarted.
