// Critic-owned security audit for the Duress PIN policy (R5 sign-off).
//
// The two properties that make duress safe, asserted exhaustively across every
// (trigger × hasDecoy) configuration:
//   1. INDISTINGUISHABILITY — a duress unlock's observable signal must always
//      equal some benign unlock's signal, and must NEVER look like opening the
//      real database.
//   2. ALWAYS-WIPES — entering the duress secret must wipe the real data in every
//      configuration; a coercer must not be able to configure the wipe away.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-15.md).

import 'package:dgvault/core/security/duress_policy.dart';
import 'package:test/test.dart';

void main() {
  final configs = [
    for (final t in DuressTrigger.values)
      for (final hasDecoy in [true, false]) DuressPolicy(trigger: t, hasDecoy: hasDecoy),
  ];

  test('a duress secret wipes the real data in EVERY configuration', () {
    for (final p in configs) {
      expect(p.resolve(CredentialMatch.duress).wipeRealData, isTrue,
          reason: 'trigger=${p.trigger} hasDecoy=${p.hasDecoy}: wipe must always fire',);
    }
  });

  test('a duress signal is always benign and never "opened the real db"', () {
    const benign = {ObservableSignal.openedDecoy, ObservableSignal.rejected};
    for (final p in configs) {
      final s = p.resolve(CredentialMatch.duress).signal;
      expect(s, isNot(ObservableSignal.openedReal),
          reason: 'duress must never be observably a real unlock',);
      expect(benign.contains(s), isTrue, reason: 'trigger=${p.trigger} hasDecoy=${p.hasDecoy}');
    }
  });

  test('duress signals are byte-identical to their benign cover', () {
    // openDecoy(+decoy) hides behind a normal decoy unlock...
    expect(
      const DuressPolicy(trigger: DuressTrigger.openDecoy, hasDecoy: true)
          .resolve(CredentialMatch.duress)
          .signal,
      const DuressPolicy().resolve(CredentialMatch.decoy).signal,
    );
    // ...silentFail (and openDecoy-without-decoy) hides behind a wrong secret.
    for (final p in [
      const DuressPolicy(trigger: DuressTrigger.silentFail),
      const DuressPolicy(trigger: DuressTrigger.openDecoy, hasDecoy: false),
    ]) {
      expect(p.resolve(CredentialMatch.duress).signal,
          const DuressPolicy().resolve(CredentialMatch.none).signal,);
    }
  });

  test('only the duress secret wipes — real/decoy/none never do', () {
    for (final m in [CredentialMatch.real, CredentialMatch.decoy, CredentialMatch.none]) {
      for (final p in configs) {
        expect(p.resolve(m).wipeRealData, isFalse, reason: '$m must not wipe');
      }
    }
  });
}
