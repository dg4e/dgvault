// dgvault — Duress PIN policy (pure routing logic).
//
// A duress secret lets a coerced user "open" their vault while secretly either
// (a) showing a harmless decoy database, or (b) destroying the real data first.
// The security property that makes this useful is INDISTINGUISHABILITY: to the
// coercer, entering a duress secret must look exactly like a normal unlock —
// same on-screen result, no error that betrays "this was the duress PIN".
//
// This module owns only the routing decision. Matching the entered secret to a
// credential (real master key / decoy key / duress secret) is the crypto
// layer's job and MUST be constant-time; the actual wipe and database opening
// are performed by the caller from the returned [DuressOutcome]. Pure and
// deterministic — fully unit-testable, and the indistinguishability invariant
// is asserted in tests.

/// Which registered credential the entered secret matched (decided upstream by
/// the constant-time crypto comparison).
enum CredentialMatch { real, decoy, duress, none }

/// What a duress secret does after the real data is wiped.
enum DuressTrigger {
  /// Wipe, then open the decoy database (looks like a normal decoy unlock).
  openDecoy,

  /// Wipe, then show the ordinary "wrong secret" rejection (looks like a typo).
  silentFail,
}

/// What an observer (the coercer) can perceive. Two outcomes with the same
/// signal are indistinguishable from the outside.
enum ObservableSignal { openedReal, openedDecoy, rejected }

class DuressOutcome {
  const DuressOutcome({
    required this.openReal,
    required this.openDecoy,
    required this.wipeRealData,
    required this.reject,
  });

  /// Open the real database.
  final bool openReal;

  /// Open the decoy database.
  final bool openDecoy;

  /// Irreversibly wipe the real local data before doing anything else. This is
  /// the hidden side effect; it is NOT part of [signal].
  final bool wipeRealData;

  /// Show the ordinary failed-unlock UI.
  final bool reject;

  /// The externally perceivable result. Crucially excludes [wipeRealData].
  ObservableSignal get signal {
    if (openReal) return ObservableSignal.openedReal;
    if (openDecoy) return ObservableSignal.openedDecoy;
    return ObservableSignal.rejected;
  }
}

class DuressPolicy {
  const DuressPolicy({
    this.trigger = DuressTrigger.openDecoy,
    this.hasDecoy = true,
  });

  /// Behaviour when a duress secret is entered.
  final DuressTrigger trigger;

  /// Whether a decoy database is configured. Required for [DuressTrigger.openDecoy].
  final bool hasDecoy;

  /// Effective trigger: `openDecoy` degrades to `silentFail` when no decoy
  /// exists (you cannot show a decoy that isn't configured).
  DuressTrigger get _effectiveTrigger =>
      (trigger == DuressTrigger.openDecoy && !hasDecoy)
          ? DuressTrigger.silentFail
          : trigger;

  DuressOutcome resolve(CredentialMatch match) {
    switch (match) {
      case CredentialMatch.real:
        return const DuressOutcome(
          openReal: true,
          openDecoy: false,
          wipeRealData: false,
          reject: false,
        );
      case CredentialMatch.decoy:
        // A decoy is a legitimate separate database the user can choose to show;
        // matching it alone never wipes anything.
        return const DuressOutcome(
          openReal: false,
          openDecoy: true,
          wipeRealData: false,
          reject: false,
        );
      case CredentialMatch.duress:
        if (_effectiveTrigger == DuressTrigger.openDecoy) {
          // Wipe (hidden) + open decoy → indistinguishable from a decoy unlock.
          return const DuressOutcome(
            openReal: false,
            openDecoy: true,
            wipeRealData: true,
            reject: false,
          );
        }
        // Wipe (hidden) + reject → indistinguishable from a wrong secret.
        return const DuressOutcome(
          openReal: false,
          openDecoy: false,
          wipeRealData: true,
          reject: true,
        );
      case CredentialMatch.none:
        return const DuressOutcome(
          openReal: false,
          openDecoy: false,
          wipeRealData: false,
          reject: true,
        );
    }
  }
}
