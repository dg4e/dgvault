import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:dgvault/core/generator/diceware_generator.dart';

void main() {
  // Small known wordlist for deterministic, verifiable assertions.
  final words = [
    'apple', 'brave', 'cloud', 'delta', 'eagle', 'flame',
    'grape', 'house', 'igloo', 'joker', 'kite', 'lemon',
  ];

  group('DicewareGenerator', () {
    DicewareGenerator gen() =>
        DicewareGenerator(wordlist: words, random: Random(7));

    test('generates the requested number of words', () {
      final g = gen();
      for (final n in [1, 4, 6, 10]) {
        final phrase = g.generate(DicewareOptions(wordCount: n, separator: '-'));
        expect(phrase.split('-').length, n, reason: 'wordCount $n');
      }
    });

    test('every chosen word comes from the wordlist', () {
      final g = gen();
      final phrase = g.generate(const DicewareOptions(wordCount: 20, separator: ' '));
      for (final w in phrase.split(' ')) {
        expect(words.contains(w), isTrue, reason: 'unknown word "$w"');
      }
    });

    test('separator is applied between words', () {
      final g = gen();
      final phrase = g.generate(const DicewareOptions(wordCount: 4, separator: '.'));
      expect(phrase.split('.').length, 4);
      expect(phrase.contains('-'), isFalse);
    });

    test('firstLetterEachWord capitalizes each word', () {
      final g = gen();
      final phrase = g.generate(const DicewareOptions(
        wordCount: 5,
        separator: '-',
        capitalization: DicewareCapitalization.firstLetterEachWord,
      ));
      for (final w in phrase.split('-')) {
        // strip any trailing digit just in case (includeNumber is off here)
        expect(w[0], equals(w[0].toUpperCase()), reason: w);
      }
    });

    test('firstWordOnly capitalizes only the first word', () {
      final g = gen();
      final phrase = g.generate(const DicewareOptions(
        wordCount: 4,
        separator: '-',
        capitalization: DicewareCapitalization.firstWordOnly,
      ));
      final parts = phrase.split('-');
      expect(parts[0][0], equals(parts[0][0].toUpperCase()));
      for (var i = 1; i < parts.length; i++) {
        expect(parts[i][0], equals(parts[i][0].toLowerCase()));
      }
    });

    test('includeNumber appends exactly one digit somewhere', () {
      final g = gen();
      final phrase = g.generate(const DicewareOptions(
        wordCount: 5,
        separator: '-',
        includeNumber: true,
      ));
      final digitCount = phrase.split('').where((c) => '0123456789'.contains(c)).length;
      expect(digitCount, 1);
    });

    test('entropy = wordCount * log2(uniqueWordlistSize)', () {
      final g = gen();
      final opts = const DicewareOptions(wordCount: 6);
      final expected = 6 * (log(words.toSet().length) / log(2));
      expect(g.estimateEntropyBits(opts), closeTo(expected, 1e-9));
    });

    test('throws on empty wordlist', () {
      expect(
        () => DicewareGenerator(wordlist: const []),
        throwsA(isA<DicewareException>()),
      );
    });

    test('throws on wordCount < 1', () {
      expect(
        () => gen().generate(const DicewareOptions(wordCount: 0)),
        throwsA(isA<DicewareException>()),
      );
    });

    test('output varies across calls (secure RNG)', () {
      final g = DicewareGenerator(wordlist: words);
      final a = g.generate(const DicewareOptions(wordCount: 8));
      final b = g.generate(const DicewareOptions(wordCount: 8));
      expect(a, isNot(equals(b)));
    });
  });
}
