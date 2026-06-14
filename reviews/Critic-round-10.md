# Critic Review — Round 10

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** verify R8 fixes; adversarial audit of search; Phase 1 escalation.

## ✅ R8 findings — fixes VERIFIED in source (signed off)
- **T1 `copyEntry` corruption — FIXED.** `copyEntry` now `_cloneEntry(entry)`
  (deep-copies fields, tags, attachments, and history into fresh objects),
  relinks the *clone*, and inserts the clone. Source entry untouched; the two
  databases hold distinct `Entry` objects. My round-8 pinning test was updated to
  assert the corrected behaviour and matches the source.
- **M1 merge data-loss — FIXED.** `DatabaseMerger.merge` now calls
  `EntryHistory.record(te)` before `_replaceContent` and `_unionHistory(te, se)`
  after, so an overwritten target version is recoverable from history and source
  history is merged in — closing the unmitigated LWW data loss.
- **M2 comparator attachment diff — FIXED** (per plan note; attachment changes now
  detected).

All findings I have raised across rounds 3–8 are now resolved. Verified each in
source per §0 — I did not take the "fixed" labels on trust.

## Search engine — APPROVE
`EntrySearch` is correct: all-fields AND-term search, protected values excluded by
default with explicit `searchProtected` opt-in (the key security property),
case-sensitivity toggle, blank-query-returns-all, tree traversal. Composer's suite
covers these. I added `entry_search_audit_test.dart` for the uncovered protection
edges:
- a protected custom field's NAME stays searchable while its VALUE is gated;
- an AND term that exists only in the protected password does not leak a match by
  default, but does under `allFields + searchProtected`.
No defects found.

## 🛑 Phase 1 escalation — round 10, core still does not exist
Restating last round, now more urgent. **Zero** of Phase 1 was built this round
(only fixes + reviews landed). After 10 rounds there is still no KDBX reader/
writer, no Argon2 KDF, no cipher layer, and no encrypted-at-rest storage. The
shipped modules are a high-quality **in-memory plaintext** library that cannot
open or save a real `.kdbx` file.

Against the task's own Technical Requirements, the following are currently **not
demonstrable at all**: KeePass XML format compatibility, encrypted local database
storage, zero-knowledge architecture, secure storage of credentials. Acceptance
§4.6 (golden `.kdbx` round-trip) and the Phase 1 Critic golden tests remain
blocked on code that has never been started.

Concrete recommendation for the next round, in priority order:
1. KDBX4 header parse/serialize + Argon2id KDF over a vetted lib (params already
   modelled in `KdfParams`).
2. AES-256/ChaCha20 inner-stream + HMAC block layer → decrypt/encrypt a real file.
3. The moment a reader exists, I will land the golden round-trip suite against
   KeePassXC-generated fixtures (contract already in `docs/testing-strategy.md`
   and `test/golden/fixtures/README.md`).
Until at least (1)+(2) exist, the product is not a password manager.

## Honesty note (§0)
Toolchain still absent; `flutter test` not executed. All assertions traced against
source by hand. Test suite on master is now ~11 files incl. 7 Critic adversarial
suites; CI runs them once a Flutter runner is available.

## Consensus
NO. The Phase 1 crypto/KDBX spine is unbuilt after 10 rounds — encrypted
persistence, zero-knowledge, and golden interop are undemonstrable. All prior
correctness findings are resolved and the in-memory modules are solid, but the
product's defining core does not exist. Phases 2/8 and much of 3/5/6/7 also
remain unstarted.
