// dgvault — Diceware wordlists.
//
// Pure Dart (no Flutter / asset / file I/O — `lib/core` must stay platform
// agnostic per the ADR). A usable default wordlist is embedded so the diceware
// generator works out of the box; for production-strength entropy a platform
// layer can read the official EFF "large" list (7776 words) from disk and pass
// the file contents to [DicewareWordlist.parseEff].
//
// Entropy scales with list size: log2(size) bits per word. The embedded list
// below yields ~log2(N) bits/word; [DicewareGenerator.estimateEntropyBits]
// reports the true value from the actual list, so security is never overstated.

/// Parsers + validation for Diceware wordlists supplied as text.
class DicewareWordlist {
  /// Parse the official EFF / classic Diceware format where each line is
  /// `<dice-digits><whitespace><word>` (e.g. `11116   abacus`). Lines without a
  /// trailing word token are ignored. Returns de-duplicated words in order.
  static List<String> parseEff(String contents) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in contents.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      // Take the last whitespace-separated token as the word.
      final parts = line.split(RegExp(r'\s+'));
      final word = parts.last.trim();
      if (word.isEmpty) continue;
      // If the line is only the dice number (no word), skip.
      if (parts.length == 1 && RegExp(r'^\d+$').hasMatch(word)) continue;
      if (seen.add(word)) out.add(word);
    }
    return out;
  }

  /// Parse a plain one-word-per-line list (blank lines and `#` comments ignored).
  static List<String> parsePlain(String contents) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in contents.split('\n')) {
      final word = raw.trim();
      if (word.isEmpty || word.startsWith('#')) continue;
      if (seen.add(word)) out.add(word);
    }
    return out;
  }

  /// True when [words] is large enough to be meaningful for passphrases.
  static bool isUsable(List<String> words) => words.toSet().length >= 64;
}

/// Embedded default wordlist: 264 distinct common English words (~8 bits/word).
/// This is a working, real-word fallback — drop in the full EFF large list via
/// [DicewareWordlist.parseEff] for ~12.9 bits/word.
const List<String> kDefaultDicewareWords = <String>[
  'able', 'acid', 'acorn', 'actor', 'agent', 'air', 'alarm', 'album',
  'alien', 'alley', 'amber', 'angel', 'anger', 'apple', 'apron', 'arch',
  'arena', 'armor', 'arrow', 'aspen', 'atlas', 'attic', 'audio', 'auto',
  'autumn', 'axis', 'bacon', 'badge', 'baker', 'banjo', 'barge', 'basil',
  'basin', 'batch', 'beach', 'beard', 'beaver', 'bench', 'berry', 'bicep',
  'bison', 'blade', 'blaze', 'blend', 'block', 'bloom', 'board', 'bonus',
  'boost', 'booth', 'brake', 'brave', 'bread', 'brick', 'bridge', 'broom',
  'brush', 'bubble', 'bucket', 'buggy', 'bunny', 'cabin', 'cable', 'cactus',
  'camel', 'candle', 'canoe', 'canyon', 'carbon', 'cargo', 'carol', 'castle',
  'cedar', 'chalk', 'charm', 'cheese', 'cherry', 'chess', 'chime', 'clamp',
  'clay', 'cliff', 'cloak', 'clock', 'cloud', 'clover', 'coast', 'cobra',
  'cocoa', 'comet', 'compass', 'copper', 'coral', 'cotton', 'cousin', 'cove',
  'crane', 'crate', 'cream', 'creek', 'crest', 'crisp', 'crown', 'crystal',
  'cube', 'curve', 'cycle', 'daisy', 'dance', 'dapper', 'dawn', 'delta',
  'denim', 'desert', 'diary', 'diesel', 'dime', 'diner', 'ditch', 'dock',
  'dolphin', 'donut', 'dragon', 'dream', 'drift', 'drum', 'eagle', 'easel',
  'ember', 'emery', 'engine', 'envoy', 'epoch', 'ethic', 'fable', 'fairy',
  'falcon', 'fancy', 'fawn', 'fence', 'fern', 'ferry', 'fiber', 'fjord',
  'flame', 'flare', 'fleet', 'flint', 'float', 'flora', 'flute', 'forest',
  'fossil', 'fox', 'frost', 'fudge', 'gable', 'galaxy', 'garden', 'gecko',
  'ginger', 'glacier', 'glide', 'globe', 'gnome', 'goblet', 'grape', 'grove',
  'guitar', 'hammer', 'harbor', 'hazel', 'heron', 'hickory', 'honey', 'hornet',
  'igloo', 'index', 'ingot', 'island', 'ivory', 'jacket', 'jaguar', 'jasper',
  'jelly', 'jewel', 'jolly', 'jungle', 'kayak', 'kettle', 'kitten', 'koala',
  'lagoon', 'lantern', 'ledge', 'lemon', 'lever', 'lilac', 'linen', 'llama',
  'locket', 'lotus', 'lunar', 'lyric', 'mango', 'maple', 'marble', 'meadow',
  'melon', 'meteor', 'mint', 'mirror', 'mitten', 'molten', 'moss', 'mural',
  'nectar', 'needle', 'nest', 'noble', 'nomad', 'oasis', 'ocean', 'olive',
  'onyx', 'orbit', 'otter', 'oxide', 'paddle', 'palace', 'panda', 'parlor',
  'pebble', 'pelican', 'penny', 'pepper', 'petal', 'pilot', 'pine', 'pixel',
  'planet', 'plaza', 'plum', 'pocket', 'pollen', 'pony', 'poppy', 'prairie',
  'prism', 'pueblo', 'puffin', 'pumpkin', 'quartz', 'quiver', 'rabbit', 'radar',
  'raven', 'ribbon', 'river', 'robin', 'rocket', 'rumble', 'saddle', 'salmon',
];
