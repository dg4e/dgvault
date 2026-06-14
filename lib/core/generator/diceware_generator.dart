// dgvault — Diceware passphrase generator.
//
// Pure Dart, no external packages. Generates passphrases by selecting words
// uniformly at random from a wordlist using [Random.secure] (overridable for
// tests). The default uses the EFF "large" wordlist (7776 words) when bundled
// as an asset; for headless/core tests a wordlist is injected directly.
//
// Entropy per word = log2(wordlistSize). For the EFF large list that is
// log2(7776) ≈ 12.925 bits/word, so a 6-word passphrase ≈ 77.5 bits.

import 'dart:math';

/// Strategy for capitalizing words in the passphrase.
enum DicewareCapitalization {
  none,
  firstLetterEachWord,
  firstWordOnly,
}

class DicewareOptions {
  /// Number of words in the passphrase. EFF recommends >= 6.
  final int wordCount;

  /// String placed between words (e.g. '-', ' ', '.').
  final String separator;

  final DicewareCapitalization capitalization;

  /// Append a random digit (0–9) to one randomly chosen word for sites that
  /// demand a number. Off by default — it adds < 3.4 bits and hurts memorability.
  final bool includeNumber;

  const DicewareOptions({
    this.wordCount = 6,
    this.separator = '-',
    this.capitalization = DicewareCapitalization.none,
    this.includeNumber = false,
  });
}

class DicewareException implements Exception {
  final String message;
  DicewareException(this.message);
  @override
  String toString() => 'DicewareException: $message';
}

class DicewareGenerator {
  final Random _random;

  /// The wordlist to draw from. Must be non-empty and should be de-duplicated
  /// for the entropy estimate to be accurate.
  final List<String> wordlist;

  DicewareGenerator({required this.wordlist, Random? random})
      : _random = random ?? Random.secure() {
    if (wordlist.isEmpty) {
      throw DicewareException('wordlist must not be empty');
    }
  }

  String generate(DicewareOptions options) {
    if (options.wordCount < 1) {
      throw DicewareException('wordCount must be >= 1');
    }

    final words = <String>[
      for (var i = 0; i < options.wordCount; i++)
        wordlist[_random.nextInt(wordlist.length)],
    ];

    _applyCapitalization(words, options.capitalization);

    if (options.includeNumber) {
      final idx = _random.nextInt(words.length);
      words[idx] = '${words[idx]}${_random.nextInt(10)}';
    }

    return words.join(options.separator);
  }

  void _applyCapitalization(List<String> words, DicewareCapitalization mode) {
    switch (mode) {
      case DicewareCapitalization.none:
        break;
      case DicewareCapitalization.firstWordOnly:
        if (words.isNotEmpty) words[0] = _capitalize(words[0]);
        break;
      case DicewareCapitalization.firstLetterEachWord:
        for (var i = 0; i < words.length; i++) {
          words[i] = _capitalize(words[i]);
        }
        break;
    }
  }

  String _capitalize(String w) =>
      w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';

  /// Bits of entropy contributed by the word selection alone (excludes the
  /// optional appended digit). Uses the de-duplicated wordlist size.
  double estimateEntropyBits(DicewareOptions options) {
    final size = wordlist.toSet().length;
    if (size < 2 || options.wordCount < 1) return 0;
    return options.wordCount * (log(size) / log(2));
  }
}
