# Critic Review — Round 11

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** KeePass inner-XML codec (`core/format/keepass_xml.dart`) — the first
real piece of the Phase 1 spine to land on master.

## Progress note
After 10 rounds of escalation, Phase 1 is moving: the inner-XML codec is merged
(Composer) and Tags/custom-fields/attachments landed (Performer). The remaining
and still-blocking piece is the **crypto envelope**: Argon2 KDF, AES/ChaCha
cipher, KDBX binary header, and encrypted-at-rest storage. No `.kdbx` file can yet
be opened or written.

## XML codec — APPROVE (with one forward-looking interop risk)
Uses `package:xml` (no hand-rolled escaping), maps meta/groups/entries/strings/
binaries/history cleanly, ISO-8601 times, flat history (asHistory guard correct).
Composer's round-trips cover structure. I added `keepass_xml_audit_test.dart` for
the content edges that XML codecs classically corrupt:
- XML metacharacters (`< > & " '`) in values,
- **whitespace-significant values under `pretty: true`** (leading/trailing spaces,
  tabs, newlines) — encoded as an invariant + bug probe (see below),
- unicode + the `Protected` flag.

### Whitespace bug-probe (honest §0 note)
The `pretty: true` whitespace test asserts the required invariant (exact
preservation). `package:xml` keeps text-only elements inline, so I expect it to
hold — but I could not execute it (no toolchain), so it doubles as a probe: if the
pretty-printer reflows text content, CI will fail this test and surface real
credential-whitespace corruption. This is the one assertion this round I have
*not* fully traced to a guaranteed pass; flagging it explicitly rather than
claiming green.

### 🟠 Forward interop risk (flag for the KDBX layer, not a current bug)
At this layer protected values are stored as **plaintext** under
`Protected="True"` — correct *only if* the KDBX layer applies/strips the KeePass
inner-stream cipher (Salsa20/ChaCha20) around this codec. In a real KeePass `.kdbx`
the decrypted inner XML has protected values **base64-encoded and inner-stream-
encrypted**, not plaintext. So when the (unbuilt) KDBX reader hands XML here, it
MUST first decrypt+decode protected values, and the writer MUST encrypt+encode
them — otherwise golden interop with KeePassXC will read ciphertext as the
password. Recorded so the boundary is built precisely; my golden round-trip suite
will assert exactly this once the KDBX layer exists.

### Minor round-trip notes
- Only `CreationTime`/`LastModificationTime` are mapped; other KeePass times
  (LastAccessTime, ExpiryTime/Expires, UsageCount, LocationChanged) are dropped
  on round-trip from a real file. Low-severity metadata loss.
- Entry-level attachment data round-trips only via the binary pool (entry
  `Binary` writes a `Ref`, not bytes) — correct for the KDBX model, but inline
  entry data not in the pool would be lost. Acceptable by design.

## Status of prior findings
All correctness findings (rounds 3–8) remain resolved (verified R10). No open
REQUEST_CHANGES this round.

## Honesty note (§0)
Toolchain absent; escaping/structure assertions traced against `package:xml`
semantics; the pretty-whitespace assertion is a probe (above). Master test suite
now ~12 files incl. 8 Critic adversarial suites.

## Consensus
NO. The crypto envelope (Argon2/cipher/KDBX header/encrypted-at-rest) is still
unbuilt, so encrypted persistence, zero-knowledge, and golden `.kdbx` interop
remain undemonstrable — acceptance §4.6 still blocked. Real progress this round,
but the product still cannot open or save an encrypted database. Phases 2/8 and
much of 3/5/6/7 also unstarted.
