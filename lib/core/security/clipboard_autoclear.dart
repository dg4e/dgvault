// dgvault — Auto-clear clipboard scheduler (pure, clock-injectable).
//
// When a secret (password, TOTP, etc.) is copied, it must be wiped from the
// clipboard after a timeout. Two correctness hazards this models:
//   1. A *newer* copy must supersede an older pending clear, so the timer for an
//      earlier secret never wipes a value the user copied afterwards.
//   2. Clearing must be cancellable (e.g. the app locks and wipes immediately).
//
// This core is platform-agnostic and deterministic: the platform layer reads
// `now` from a real clock and schedules a callback at `copy.clearAt`; when that
// fires it asks [shouldClear]. No `dart:async` Timer here so it is unit-testable
// by driving time by hand. No secret is retained — only a generation + instants.

/// A pending auto-clear, returned by [ClipboardClearController.copy].
class ClipboardCopy {
  ClipboardCopy({
    required this.generation,
    required this.copiedAt,
    required this.clearAt,
  });

  /// Monotonic id; only the controller's latest generation is "current".
  final int generation;
  final DateTime copiedAt;
  final DateTime clearAt;

  /// Time left until this copy is due to be cleared (zero once due).
  Duration remaining(DateTime now) {
    final r = clearAt.difference(now);
    return r.isNegative ? Duration.zero : r;
  }
}

class ClipboardClearController {
  ClipboardClearController({this.timeout = const Duration(seconds: 30)})
      : assert(timeout > Duration.zero, 'timeout must be positive');

  /// How long a copied secret may live on the clipboard.
  final Duration timeout;

  int _generation = 0;

  /// Generation of the most recent copy (0 = nothing copied yet).
  int get currentGeneration => _generation;

  /// Record a sensitive copy made at [now]. Supersedes any prior pending clear.
  ClipboardCopy copy(DateTime now) {
    _generation++;
    return ClipboardCopy(
      generation: _generation,
      copiedAt: now,
      clearAt: now.add(timeout),
    );
  }

  /// True when [copy] is still the latest copy (no newer copy / cancel since).
  bool isCurrent(ClipboardCopy copy) => copy.generation == _generation;

  /// Whether [copy] should be wiped at [now]: it is still current AND its
  /// clear instant has arrived. A superseded copy never reports true, so an old
  /// timer cannot clobber a newer clipboard value.
  bool shouldClear(ClipboardCopy copy, DateTime now) =>
      isCurrent(copy) && !now.isBefore(copy.clearAt);

  /// Cancel any pending clear (e.g. the secret was already wiped on lock). Any
  /// outstanding [ClipboardCopy] becomes non-current.
  void cancel() => _generation++;
}
