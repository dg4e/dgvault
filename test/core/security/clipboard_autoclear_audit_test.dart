// Critic-owned security audit for the clipboard auto-clear scheduler.
//
// Performer's suite covers schedule/boundary/supersede(isCurrent)/cancel/
// remaining/generation. This pins the ONE end-to-end security assertion it stops
// just short of: a superseded copy's `shouldClear` must be false even AT/AFTER
// its own clearAt — i.e. an old secret's timer can never wipe the newer clipboard
// value the user copied afterwards. (Performer asserts `isCurrent` is false;
// this asserts the consequence at the dangerous instant.)
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-16.md).

import 'package:dgvault/core/security/clipboard_autoclear.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  test('a superseded copy never clears, even past its own clearAt', () {
    final c = ClipboardClearController(timeout: const Duration(seconds: 30));
    final first = c.copy(t0); // clearAt = t0 + 30s
    c.copy(t0.add(const Duration(seconds: 5))); // gen2 supersedes first

    // 60s in — well beyond first.clearAt — the stale timer must stay inert.
    expect(c.shouldClear(first, t0.add(const Duration(seconds: 60))), isFalse,
        reason: 'an old timer must not wipe the newer clipboard value');
  });

  test('cancel() inerts a pending clear at and after its clearAt', () {
    final c = ClipboardClearController(timeout: const Duration(seconds: 30));
    final copy = c.copy(t0);
    c.cancel(); // e.g. secret already wiped on app lock
    expect(c.shouldClear(copy, t0.add(const Duration(seconds: 45))), isFalse);
  });

  test('the current copy clears exactly at its clearAt boundary, not before', () {
    final c = ClipboardClearController(timeout: const Duration(seconds: 30));
    final copy = c.copy(t0);
    expect(c.shouldClear(copy, t0.add(const Duration(seconds: 29))), isFalse);
    expect(c.shouldClear(copy, t0.add(const Duration(seconds: 30))), isTrue);
  });
}
