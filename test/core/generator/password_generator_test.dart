import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:dgvault/core/generator/password_generator.dart';

void main() {
  group('PasswordGenerator', () {
    // Seeded RNG → deterministic, but assertions are property-based so they hold
    // for any RNG. The seed just keeps failures reproducible.
    PasswordGenerator gen() => PasswordGenerator(random: Random(42));

    test('produces the requested length', () {
      final g = gen();
      for (final len in [1, 8, 20, 64, 200]) {
        final pw = g.generate(PasswordOptions(length: len));
        expect(pw.length, len, reason: 'length $len');
      }
    });

    test('only uses characters from the enabled pool', () {
      final g = gen();
      final pw = g.generate(const PasswordOptions(
        length: 100,
        useLowercase: true,
        useUppercase: false,
        useDigits: true,
        useSymbols: false,
      ));
      final allowed = (kLowercase + kDigits).split('').toSet();
      for (final ch in pw.split('')) {
        expect(allowed.contains(ch), isTrue, reason: 'unexpected char "$ch"');
      }
    });

    test('requireEachSelectedClass includes >=1 char from every class', () {
      final g = gen();
      // Run several times; the guarantee must hold every time.
      for (var i = 0; i < 50; i++) {
        final pw = g.generate(const PasswordOptions(length: 8));
        expect(pw.split('').any(kLowercase.contains), isTrue, reason: 'lower');
        expect(pw.split('').any(kUppercase.contains), isTrue, reason: 'upper');
        expect(pw.split('').any(kDigits.contains), isTrue, reason: 'digit');
        expect(pw.split('').any(kSymbols.contains), isTrue, reason: 'symbol');
      }
    });

    test('excludeAmbiguous removes confusable characters', () {
      final g = gen();
      final pw = g.generate(const PasswordOptions(
        length: 300,
        excludeAmbiguous: true,
      ));
      for (final ch in kAmbiguousCharacters.split('')) {
        expect(pw.contains(ch), isFalse, reason: 'ambiguous "$ch" present');
      }
    });

    test('excludeCharacters removes specific characters', () {
      final g = gen();
      final pw = g.generate(const PasswordOptions(
        length: 300,
        excludeCharacters: 'aeiou',
        requireEachSelectedClass: false,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
      ));
      for (final ch in 'aeiou'.split('')) {
        expect(pw.contains(ch), isFalse);
      }
    });

    test('customCharacterSet overrides built-in classes', () {
      final g = gen();
      final pw = g.generate(const PasswordOptions(
        length: 50,
        customCharacterSet: 'ABC',
      ));
      expect(RegExp(r'^[ABC]+$').hasMatch(pw), isTrue, reason: pw);
    });

    test('extraCharacters are added to the pool', () {
      final g = gen();
      final pw = g.generate(const PasswordOptions(
        length: 500,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
        extraCharacters: '€', // not in any built-in class
        requireEachSelectedClass: false,
      ));
      final allowed = (kLowercase + '€').split('').toSet();
      for (final ch in pw.split('')) {
        expect(allowed.contains(ch), isTrue);
      }
    });

    test('throws when no characters are available', () {
      final g = gen();
      expect(
        () => g.generate(const PasswordOptions(
          useLowercase: false,
          useUppercase: false,
          useDigits: false,
          useSymbols: false,
        )),
        throwsA(isA<PasswordGenerationException>()),
      );
    });

    test('throws when length < 1', () {
      expect(
        () => gen().generate(const PasswordOptions(length: 0)),
        throwsA(isA<PasswordGenerationException>()),
      );
    });

    test('throws when length too short for all required classes', () {
      // 4 classes required but length 3.
      expect(
        () => gen().generate(const PasswordOptions(length: 3)),
        throwsA(isA<PasswordGenerationException>()),
      );
    });

    test('entropy estimate matches length * log2(poolSize)', () {
      final g = gen();
      // lowercase only → pool 26.
      const opts = PasswordOptions(
        length: 10,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
      );
      final expected = 10 * (log(26) / log(2));
      expect(g.estimateEntropyBits(opts), closeTo(expected, 1e-9));
    });

    test('output varies across calls (sanity, secure RNG)', () {
      final g = PasswordGenerator(); // real secure RNG
      final a = g.generate(const PasswordOptions(length: 32));
      final b = g.generate(const PasswordOptions(length: 32));
      expect(a, isNot(equals(b)));
    });
  });
}
