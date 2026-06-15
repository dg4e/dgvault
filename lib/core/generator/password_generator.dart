// dgvault — configurable & customizable password generator.
//
// Pure Dart, no external packages. Uses [Random.secure] by default so generated
// secrets are drawn from a cryptographically secure source. A [Random] may be
// injected for deterministic testing.
//
// "Configurable"  → toggle character classes, length, ambiguity exclusion.
// "Customizable"  → supply an arbitrary custom character set and/or extra
//                   characters, exclude specific characters, and require that at
//                   least one character from each selected class appears.

import 'dart:math';

/// Characters that are easy to confuse visually. Excluded when
/// [PasswordOptions.excludeAmbiguous] is set.
const String kAmbiguousCharacters = 'Il1O0o5S2Z8B|`\'"{}[]()/\\';

/// Built-in character classes.
const String kLowercase = 'abcdefghijklmnopqrstuvwxyz';
const String kUppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const String kDigits = '0123456789';
const String kSymbols = '!@#\$%^&*()-_=+[]{};:,.<>?/|~';

/// Options controlling password generation.
///
/// When [customCharacterSet] is non-null it fully overrides the built-in class
/// toggles — only those characters (minus [excludeCharacters] and, if requested,
/// ambiguous characters) are used.
class PasswordOptions {
  final int length;
  final bool useLowercase;
  final bool useUppercase;
  final bool useDigits;
  final bool useSymbols;

  /// Extra characters appended to the pool (customization).
  final String extraCharacters;

  /// Characters removed from the pool (customization).
  final String excludeCharacters;

  /// Remove visually ambiguous characters ([kAmbiguousCharacters]).
  final bool excludeAmbiguous;

  /// Guarantee at least one character from every *selected* class.
  final bool requireEachSelectedClass;

  /// If non-null, use exactly this set instead of the built-in classes.
  final String? customCharacterSet;

  const PasswordOptions({
    this.length = 20,
    this.useLowercase = true,
    this.useUppercase = true,
    this.useDigits = true,
    this.useSymbols = true,
    this.extraCharacters = '',
    this.excludeCharacters = '',
    this.excludeAmbiguous = false,
    this.requireEachSelectedClass = true,
    this.customCharacterSet,
  });

  PasswordOptions copyWith({
    int? length,
    bool? useLowercase,
    bool? useUppercase,
    bool? useDigits,
    bool? useSymbols,
    String? extraCharacters,
    String? excludeCharacters,
    bool? excludeAmbiguous,
    bool? requireEachSelectedClass,
    String? customCharacterSet,
  }) {
    return PasswordOptions(
      length: length ?? this.length,
      useLowercase: useLowercase ?? this.useLowercase,
      useUppercase: useUppercase ?? this.useUppercase,
      useDigits: useDigits ?? this.useDigits,
      useSymbols: useSymbols ?? this.useSymbols,
      extraCharacters: extraCharacters ?? this.extraCharacters,
      excludeCharacters: excludeCharacters ?? this.excludeCharacters,
      excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
      requireEachSelectedClass:
          requireEachSelectedClass ?? this.requireEachSelectedClass,
      customCharacterSet: customCharacterSet ?? this.customCharacterSet,
    );
  }
}

/// Thrown when the options cannot produce a password (empty pool, length < 1,
/// or more required classes than the requested length).
class PasswordGenerationException implements Exception {
  final String message;
  PasswordGenerationException(this.message);
  @override
  String toString() => 'PasswordGenerationException: $message';
}

class PasswordGenerator {
  final Random _random;

  /// Defaults to a cryptographically secure RNG. Inject a seeded [Random] only
  /// for tests.
  PasswordGenerator({Random? random}) : _random = random ?? Random.secure();

  /// The character classes that are active given [options], each already
  /// filtered for excluded/ambiguous characters and de-duplicated. Empty
  /// classes are dropped.
  List<String> _activeClasses(PasswordOptions options) {
    final exclude = <String>{
      ...options.excludeCharacters.split(''),
      if (options.excludeAmbiguous) ...kAmbiguousCharacters.split(''),
    };

    String filter(String src) {
      final seen = <String>{};
      final buf = StringBuffer();
      for (final ch in src.split('')) {
        if (exclude.contains(ch)) continue;
        if (seen.add(ch)) buf.write(ch);
      }
      return buf.toString();
    }

    if (options.customCharacterSet != null) {
      final custom = filter(options.customCharacterSet! + options.extraCharacters);
      return custom.isEmpty ? <String>[] : [custom];
    }

    final classes = <String>[];
    if (options.useLowercase) classes.add(kLowercase);
    if (options.useUppercase) classes.add(kUppercase);
    if (options.useDigits) classes.add(kDigits);
    if (options.useSymbols) classes.add(kSymbols);
    if (options.extraCharacters.isNotEmpty) classes.add(options.extraCharacters);

    return classes.map(filter).where((c) => c.isNotEmpty).toList();
  }

  /// Generate a single password.
  String generate(PasswordOptions options) {
    if (options.length < 1) {
      throw PasswordGenerationException('length must be >= 1');
    }
    final classes = _activeClasses(options);
    if (classes.isEmpty) {
      throw PasswordGenerationException(
          'no characters available — enable a class or provide a custom set',);
    }

    final pool = classes.join();

    if (options.requireEachSelectedClass && classes.length > options.length) {
      throw PasswordGenerationException(
          'length ${options.length} too short to include all '
          '${classes.length} required classes');
    }

    final chars = <String>[];

    // Guarantee one from each class first (when requested).
    if (options.requireEachSelectedClass) {
      for (final cls in classes) {
        chars.add(cls[_random.nextInt(cls.length)]);
      }
    }

    // Fill the remainder from the combined pool.
    while (chars.length < options.length) {
      chars.add(pool[_random.nextInt(pool.length)]);
    }

    _shuffle(chars);
    return chars.join();
  }

  /// Fisher–Yates shuffle using the injected RNG (so the guaranteed leading
  /// class characters are not positionally predictable).
  void _shuffle(List<String> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  /// Shannon entropy (bits) for a uniformly random password of [options.length]
  /// drawn from the effective pool. This is the standard `length * log2(poolSize)`
  /// estimate; the require-each-class constraint slightly lowers true entropy but
  /// the difference is negligible for typical lengths, so we report the upper bound.
  double estimateEntropyBits(PasswordOptions options) {
    final classes = _activeClasses(options);
    if (classes.isEmpty || options.length < 1) return 0;
    final poolSize = classes.join().split('').toSet().length;
    return options.length * (log(poolSize) / log(2));
  }
}
