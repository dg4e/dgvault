import 'package:dgvault/core/security/clipboard_autoclear.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

  group('ClipboardClearController', () {
    test('copy schedules clearAt = copiedAt + timeout', () {
      final c = ClipboardClearController(timeout: const Duration(seconds: 30));
      final copy = c.copy(t0);
      expect(copy.clearAt, t0.add(const Duration(seconds: 30)));
      expect(copy.copiedAt, t0);
    });

    test('not due before timeout, due at and after', () {
      final c = ClipboardClearController(timeout: const Duration(seconds: 30));
      final copy = c.copy(t0);
      expect(c.shouldClear(copy, t0.add(const Duration(seconds: 29))), isFalse);
      expect(c.shouldClear(copy, t0.add(const Duration(seconds: 30))), isTrue);
      expect(c.shouldClear(copy, t0.add(const Duration(seconds: 31))), isTrue);
    });

    test('a newer copy supersedes the older pending clear', () {
      final c = ClipboardClearController(timeout: const Duration(seconds: 30));
      final first = c.copy(t0);
      final second = c.copy(t0.add(const Duration(seconds: 5)));
      final wayLater = t0.add(const Duration(minutes: 5));
      // The first copy's timer must NOT fire — it would wipe the newer secret.
      expect(c.isCurrent(first), isFalse);
      expect(c.shouldClear(first, wayLater), isFalse);
      // The latest copy clears on its own schedule.
      expect(c.isCurrent(second), isTrue);
      expect(c.shouldClear(second, second.clearAt), isTrue);
    });

    test('cancel makes the outstanding copy non-current', () {
      final c = ClipboardClearController(timeout: const Duration(seconds: 30));
      final copy = c.copy(t0);
      c.cancel();
      expect(c.isCurrent(copy), isFalse);
      expect(c.shouldClear(copy, t0.add(const Duration(minutes: 1))), isFalse);
    });

    test('remaining counts down and clamps at zero', () {
      final c = ClipboardClearController(timeout: const Duration(seconds: 30));
      final copy = c.copy(t0);
      expect(copy.remaining(t0), const Duration(seconds: 30));
      expect(copy.remaining(t0.add(const Duration(seconds: 10))),
          const Duration(seconds: 20),);
      expect(copy.remaining(t0.add(const Duration(seconds: 45))), Duration.zero);
    });

    test('generation increments per copy', () {
      final c = ClipboardClearController();
      expect(c.currentGeneration, 0);
      c.copy(t0);
      c.copy(t0);
      expect(c.currentGeneration, 2);
    });
  });
}
