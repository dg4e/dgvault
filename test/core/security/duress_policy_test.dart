import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('routing', () {
    test('real secret opens the real database, no wipe', () {
      const p = DuressPolicy();
      final o = p.resolve(CredentialMatch.real);
      expect(o.openReal, isTrue);
      expect(o.wipeRealData, isFalse);
      expect(o.signal, ObservableSignal.openedReal);
    });

    test('decoy secret opens the decoy, no wipe', () {
      const p = DuressPolicy();
      final o = p.resolve(CredentialMatch.decoy);
      expect(o.openDecoy, isTrue);
      expect(o.wipeRealData, isFalse);
      expect(o.signal, ObservableSignal.openedDecoy);
    });

    test('no match is rejected', () {
      final o = const DuressPolicy().resolve(CredentialMatch.none);
      expect(o.reject, isTrue);
      expect(o.wipeRealData, isFalse);
      expect(o.signal, ObservableSignal.rejected);
    });

    test('duress (openDecoy) wipes then opens the decoy', () {
      const p = DuressPolicy(trigger: DuressTrigger.openDecoy);
      final o = p.resolve(CredentialMatch.duress);
      expect(o.wipeRealData, isTrue);
      expect(o.openDecoy, isTrue);
    });

    test('duress (silentFail) wipes then rejects', () {
      const p = DuressPolicy(trigger: DuressTrigger.silentFail);
      final o = p.resolve(CredentialMatch.duress);
      expect(o.wipeRealData, isTrue);
      expect(o.reject, isTrue);
    });

    test('openDecoy degrades to silentFail when no decoy is configured', () {
      const p = DuressPolicy(trigger: DuressTrigger.openDecoy, hasDecoy: false);
      final o = p.resolve(CredentialMatch.duress);
      expect(o.wipeRealData, isTrue);
      expect(o.reject, isTrue);
      expect(o.openDecoy, isFalse);
    });
  });

  group('indistinguishability invariant', () {
    test('duress(openDecoy) is observably identical to a normal decoy unlock', () {
      const p = DuressPolicy(trigger: DuressTrigger.openDecoy);
      final duress = p.resolve(CredentialMatch.duress);
      final decoy = p.resolve(CredentialMatch.decoy);
      // Same external signal; the only difference is the hidden wipe.
      expect(duress.signal, decoy.signal);
      expect(duress.signal, ObservableSignal.openedDecoy);
      expect(duress.wipeRealData, isTrue);
      expect(decoy.wipeRealData, isFalse);
    });

    test('duress(silentFail) is observably identical to a wrong secret', () {
      const p = DuressPolicy(trigger: DuressTrigger.silentFail);
      final duress = p.resolve(CredentialMatch.duress);
      final none = p.resolve(CredentialMatch.none);
      expect(duress.signal, none.signal);
      expect(duress.signal, ObservableSignal.rejected);
      // Hidden difference only.
      expect(duress.wipeRealData, isTrue);
      expect(none.wipeRealData, isFalse);
    });
  });
}
