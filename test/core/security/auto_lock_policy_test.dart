import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  group('AutoLockPolicy', () {
    test('zero timeouts disable both triggers', () {
      const p = AutoLockPolicy();
      expect(p.idleEnabled, isFalse);
      expect(p.focusEnabled, isFalse);
      expect(p.shouldLockOnIdle(t0, t0.add(const Duration(hours: 1))), isFalse);
      expect(
          p.shouldLockOnRefocus(t0, t0.add(const Duration(hours: 1))), isFalse,);
    });

    test('idle locks once the timeout elapses', () {
      const p = AutoLockPolicy(idleTimeout: Duration(minutes: 5));
      expect(p.shouldLockOnIdle(t0, t0.add(const Duration(minutes: 4))),
          isFalse,);
      expect(p.shouldLockOnIdle(t0, t0.add(const Duration(minutes: 5))), isTrue);
    });

    test('refocus locks once the focus timeout elapses', () {
      const p = AutoLockPolicy(focusTimeout: Duration(minutes: 2));
      expect(p.shouldLockOnRefocus(t0, t0.add(const Duration(minutes: 1))),
          isFalse,);
      expect(
          p.shouldLockOnRefocus(t0, t0.add(const Duration(minutes: 2))), isTrue,);
    });
  });
}
