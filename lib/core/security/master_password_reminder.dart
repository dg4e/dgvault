// dgvault — Regular master-password reminders.
//
// Periodically prompts the user to re-enter their master password so they don't
// forget it (a forgotten master password means permanent data loss — there is
// no recovery in a zero-knowledge design). Pure scheduling logic: given when the
// password was last successfully verified and an interval, decide whether a
// reminder is due now, honouring a user "snooze". The clock is passed in, so the
// scheduler is deterministic and fully unit-testable. Persisting the state and
// showing the prompt are the caller's concern.

class ReminderPolicy {
  const ReminderPolicy({
    this.interval = const Duration(days: 14),
    this.enabled = true,
  });

  /// How long after the last verification a reminder becomes due.
  final Duration interval;
  final bool enabled;
}

class ReminderState {
  const ReminderState({this.lastVerified, this.snoozedUntil});

  /// When the master password was last successfully entered (null = never).
  final DateTime? lastVerified;

  /// If set, no reminder fires before this instant (user chose "remind later").
  final DateTime? snoozedUntil;

  ReminderState copyWith({
    DateTime? lastVerified,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) {
    return ReminderState(
      lastVerified: lastVerified ?? this.lastVerified,
      snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
    );
  }
}

class MasterPasswordReminder {
  const MasterPasswordReminder(this.policy);

  final ReminderPolicy policy;

  /// The instant the next reminder becomes due, or null when reminders are
  /// disabled. A "never verified" vault is due immediately (returns [now]); a
  /// snooze later than the interval-based due time wins.
  DateTime? nextDueAt(ReminderState state, DateTime now) {
    if (!policy.enabled) return null;
    final base =
        state.lastVerified == null ? now : state.lastVerified!.add(policy.interval);
    final snooze = state.snoozedUntil;
    if (snooze != null && snooze.isAfter(base)) return snooze;
    return base;
  }

  /// Whether a reminder should be shown at [now].
  bool isDue(ReminderState state, DateTime now) {
    final due = nextDueAt(state, now);
    if (due == null) return false;
    return !now.isBefore(due); // now >= due
  }

  /// State to persist after the user successfully verifies the master password.
  /// Clears any pending snooze and resets the interval clock.
  ReminderState markVerified(ReminderState state, DateTime now) =>
      ReminderState(lastVerified: now);

  /// State to persist when the user defers the reminder by [by].
  ReminderState snooze(ReminderState state, DateTime now, Duration by) =>
      state.copyWith(snoozedUntil: now.add(by));
}
