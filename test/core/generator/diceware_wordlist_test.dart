import 'dart:math';

import 'package:test/test.dart';
import 'package:dgvault/core/generator/diceware_wordlist.dart';
import 'package:dgvault/core/generator/diceware_generator.dart';

void main() {
  group('embedded default wordlist', () {
    test('is non-trivial, de-duplicated, and usable', () {
      expect(kDefaultDicewareWords.length, greaterThanOrEqualTo(256));
      expect(kDefaultDicewareWords.toSet().length, kDefaultDicewareWords.length,
          reason: 'no duplicates',);
      expect(DicewareWordlist.isUsable(kDefaultDicewareWords), isTrue);
      for (final w in kDefaultDicewareWords) {
        expect(w, matches(RegExp(r'^[a-z]+$')), reason: w);
      }
    });
  });

  group('DicewareGenerator.standard', () {
    test('produces a passphrase from the embedded list', () {
      final g = DicewareGenerator.standard(random: Random(1));
      final phrase = g.generate(const DicewareOptions(wordCount: 6, separator: '-'));
      final parts = phrase.split('-');
      expect(parts, hasLength(6));
      for (final w in parts) {
        expect(kDefaultDicewareWords.contains(w), isTrue, reason: w);
      }
    });

    test('entropy reflects the embedded list size', () {
      final g = DicewareGenerator.standard(random: Random(1));
      final bits = g.estimateEntropyBits(const DicewareOptions(wordCount: 6));
      final expected = 6 * (log(kDefaultDicewareWords.length) / log(2));
      expect(bits, closeTo(expected, 1e-9));
    });
  });

  group('DicewareWordlist.parseEff', () {
    test('extracts words from dice-number lines', () {
      const eff = '11111\tabacus\n'
          '11112\tabdomen\n'
          '11113\tabide\n';
      final words = DicewareWordlist.parseEff(eff);
      expect(words, ['abacus', 'abdomen', 'abide']);
    });

    test('ignores blanks, comments, and dice-only lines; de-dupes', () {
      const eff = '# header\n'
          '\n'
          '11111\tapple\n'
          '11111\tapple\n' // duplicate
          '22222\n'; // dice number with no word
      final words = DicewareWordlist.parseEff(eff);
      expect(words, ['apple']);
    });

    test('parsed EFF list drives the generator', () {
      final words = DicewareWordlist.parseEff(
          '11111 alpha\n11112 bravo\n11113 charlie\n11114 delta\n',);
      final g = DicewareGenerator(wordlist: words, random: Random(3));
      final phrase = g.generate(const DicewareOptions(wordCount: 3, separator: ' '));
      for (final w in phrase.split(' ')) {
        expect(words.contains(w), isTrue);
      }
    });
  });

  group('DicewareWordlist.parsePlain', () {
    test('one word per line, ignores comments/blanks, de-dupes', () {
      const list = 'apple\n# comment\n\nbanana\napple\ncherry\n';
      expect(DicewareWordlist.parsePlain(list), ['apple', 'banana', 'cherry']);
    });

    test('isUsable is false for tiny lists', () {
      expect(DicewareWordlist.isUsable(['a', 'b', 'c']), isFalse);
    });
  });
}
