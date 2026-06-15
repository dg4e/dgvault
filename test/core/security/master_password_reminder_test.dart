import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2025, 1, 1);
  const reminder =
      MasterPasswordReminder(ReminderPolicy(interval: Duration(days: 14)));

  test('never verified → due immediately', () {
    const state = ReminderState();
    expect(reminder.isDue(state, t0), isTrue);
    expect(reminder.nextDueAt(state, t0), t0);
  });

  test('not due before the interval elapses', () {
    final state = ReminderState(lastVerified: t0);
    expect(reminder.isDue(state, t0.add(const Duration(days: 13))), isFalse);
    expect(reminder.nextDueAt(state, t0), t0.add(const Duration(days: 14)));
  });

  test('due once the interval has elapsed', () {
    final state = ReminderState(lastVerified: t0);
    expect(reminder.isDue(state, t0.add(const Duration(days: 14))), isTrue);
    expect(reminder.isDue(state, t0.add(const Duration(days: 30))), isTrue);
  });

  test('snooze suppresses an otherwise-due reminder', () {
    final overdue = ReminderState(lastVerified: t0); // due at day 14
    final now = t0.add(const Duration(days: 20)); // already overdue
    final snoozed = reminder.snooze(overdue, now, const Duration(days: 2));

    expect(reminder.isDue(snoozed, now), isFalse);
    expect(reminder.isDue(snoozed, now.add(const Duration(days: 1))), isFalse);
    expect(reminder.isDue(snoozed, now.add(const Duration(days: 2))), isTrue);
  });

  test('verifying resets the clock and clears a snooze', () {
    final snoozed = ReminderState(
      lastVerified: t0,
      snoozedUntil: t0.add(const Duration(days: 100)),
    );
    final verified = reminder.markVerified(snoozed, t0.add(const Duration(days: 20)));
    expect(verified.snoozedUntil, isNull);
    expect(verified.lastVerified, t0.add(const Duration(days: 20)));
    // Not due again until 14 days after the new verification.
    expect(reminder.isDue(verified, t0.add(const Duration(days: 33))), isFalse);
    expect(reminder.isDue(verified, t0.add(const Duration(days: 34))), isTrue);
  });

  test('disabled policy is never due', () {
    const off = MasterPasswordReminder(ReminderPolicy(enabled: false));
    expect(off.isDue(const ReminderState(), t0), isFalse);
    expect(off.nextDueAt(const ReminderState(), t0), isNull);
  });

  test('snooze shorter than remaining interval does not bring it forward', () {
    final state = ReminderState(lastVerified: t0); // due day 14
    final snoozed = reminder.snooze(state, t0.add(const Duration(days: 2)),
        const Duration(days: 1),); // snooze to day 3 (< day 14)
    // Interval-based due (day 14) still wins over the earlier snooze.
    expect(reminder.nextDueAt(snoozed, t0), t0.add(const Duration(days: 14)));
  });
}
