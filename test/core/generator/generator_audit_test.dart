// Critic-owned adversarial audit tests for the password & diceware generators.
//
// These complement Performer's author-written tests by targeting BOUNDARY bugs
// that property assertions on a single output would not catch — chiefly RNG
// index-range errors (e.g. `nextInt(len - 1)` starving the last element) and
// filter-empties-the-pool edge cases.
//
// Reachability tests use a fixed seed and a large sample so they are
// deterministic: the probability that a reachable symbol is missed across N
// draws is k * ((k-1)/k)^N, which is astronomically small for the N used here,
// for ANY seed.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:dgvault/core/generator/password_generator.dart';
import 'package:dgvault/core/generator/diceware_generator.dart';

void main() {
  group('PasswordGenerator — boundary audit', () {
    test('every character of a custom set is reachable (no nextInt off-by-one)',
        () {
      final g = PasswordGenerator(random: Random(12345));
      final seen = <String>{};
      // 3-symbol set; 3000 chars makes a missed symbol effectively impossible
      // unless the RNG index range is wrong.
      final pw = g.generate(const PasswordOptions(
        length: 3000,
        customCharacterSet: 'XYZ',
      ));
      seen.addAll(pw.split(''));
      expect(seen, equals({'X', 'Y', 'Z'}),
          reason: 'a custom-set char was never produced — index range bug?');
    });

    test('customCharacterSet emptied by excludeAmbiguous throws (no silent empty pool)',
        () {
      final g = PasswordGenerator(random: Random(1));
      // Every char here is in kAmbiguousCharacters, so the effective pool is empty.
      expect(
        () => g.generate(const PasswordOptions(
          length: 16,
          customCharacterSet: 'Il1O0',
          excludeAmbiguous: true,
        )),
        throwsA(isA<PasswordGenerationException>()),
        reason: 'an emptied pool must throw, not produce a degenerate password',
      );
    });

    test('length==1 with requireEachSelectedClass=false does not throw', () {
      // Guard against the require-classes length check firing when it should not.
      final g = PasswordGenerator(random: Random(2));
      final pw = g.generate(const PasswordOptions(
        length: 1,
        requireEachSelectedClass: false,
      ));
      expect(pw.length, 1);
    });

    test('extraCharacters duplicating a built-in class keeps length correct', () {
      final g = PasswordGenerator(random: Random(3));
      final pw = g.generate(const PasswordOptions(
        length: 40,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
        extraCharacters: 'a', // already present in kLowercase
        requireEachSelectedClass: true,
      ));
      expect(pw.length, 40);
      final allowed = kLowercase.split('').toSet();
      for (final ch in pw.split('')) {
        expect(allowed.contains(ch), isTrue, reason: 'unexpected "$ch"');
      }
    });

    test('entropy estimate de-duplicates overlapping extra characters', () {
      final g = PasswordGenerator(random: Random(4));
      // lowercase (26) + extra 'a' (dup) → effective pool still 26.
      const opts = PasswordOptions(
        length: 10,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
        extraCharacters: 'a',
      );
      expect(g.estimateEntropyBits(opts), closeTo(10 * (log(26) / log(2)), 1e-9));
    });
  });

  group('DicewareGenerator — boundary audit', () {
    final words = List<String>.generate(16, (i) => 'w$i'); // w0..w15, all unique

    test('every word in the list is reachable (no nextInt off-by-one)', () {
      final g = DicewareGenerator(wordlist: words, random: Random(99));
      final phrase =
          g.generate(const DicewareOptions(wordCount: 6000, separator: ' '));
      final produced = phrase.split(' ').toSet();
      expect(produced, equals(words.toSet()),
          reason: 'a wordlist entry (likely the last) was never selected');
    });

    test('includeNumber adds exactly one digit and does not change word count',
        () {
      final g = DicewareGenerator(wordlist: words, random: Random(5));
      final phrase = g.generate(const DicewareOptions(
        wordCount: 7,
        separator: '-',
        includeNumber: true,
      ));
      expect(phrase.split('-').length, 7, reason: 'word count must be stable');
      final digits = phrase.split('').where((c) => '0123456789'.contains(c));
      expect(digits.length, 1);
    });

    test('entropy excludes the optional appended digit', () {
      final g = DicewareGenerator(wordlist: words, random: Random(6));
      const opts = DicewareOptions(wordCount: 6, includeNumber: true);
      // Word-selection entropy only: 6 * log2(16) = 24 bits.
      expect(g.estimateEntropyBits(opts), closeTo(24.0, 1e-9));
    });

    test('single-word duplicate list reports zero entropy (size < 2 guard)', () {
      final g = DicewareGenerator(wordlist: const ['same', 'same'], random: Random(8));
      expect(g.estimateEntropyBits(const DicewareOptions(wordCount: 6)), 0);
    });
  });
}
