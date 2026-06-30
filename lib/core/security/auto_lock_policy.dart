// dgvault — Auto-lock timing policy (pure, clock-injectable).
//
// Decides when an unlocked vault should re-lock itself:
//   • idle:  no user interaction for [idleTimeout]
//   • focus: the app lost focus (backgrounded / switched away) [focusTimeout]
//     ago and has now come back.
// A zero timeout disables that trigger. No timers or I/O here — the UI layer
// drives the clock and acts on the decision, so this is unit-testable headless.

class AutoLockPolicy {
  const AutoLockPolicy({
    this.idleTimeout = Duration.zero,
    this.focusTimeout = Duration.zero,
  });

  /// Lock after this much inactivity (Duration.zero = disabled).
  final Duration idleTimeout;

  /// Lock if the app was out of focus at least this long (Duration.zero =
  /// disabled).
  final Duration focusTimeout;

  bool get idleEnabled => idleTimeout > Duration.zero;
  bool get focusEnabled => focusTimeout > Duration.zero;

  /// Whether to lock now given the last user interaction at [lastActivity].
  bool shouldLockOnIdle(DateTime lastActivity, DateTime now) =>
      idleEnabled && now.difference(lastActivity) >= idleTimeout;

  /// Whether to lock now that focus has returned, having been lost at
  /// [focusLostAt].
  bool shouldLockOnRefocus(DateTime focusLostAt, DateTime now) =>
      focusEnabled && now.difference(focusLostAt) >= focusTimeout;
}
