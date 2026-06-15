// dgvault — Markdown notes parser (render-agnostic).
//
// Parses a bounded, well-defined Markdown subset for entry Notes into a small
// AST of blocks + inline spans. Pure Dart — no rendering, no HTML — so it is
// fully unit-testable; the UI layer maps the AST to Flutter widgets (or any
// renderer). Producing an AST rather than HTML also avoids HTML-injection
// concerns entirely (no raw HTML is ever emitted from user notes).
//
// Supported blocks: ATX headings (#..######), fenced code (``` ... ```),
//   blockquotes (> ), unordered lists (-, *, +), ordered lists (N.), and
//   paragraphs (blank-line separated).
// Supported inline: `code`, **bold**/__bold__, *italic*/_italic_, [text](url),
//   bare-URL autolink, and backslash escapes.

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

abstract class MdBlock {}

class MdHeading extends MdBlock {
  MdHeading(this.level, this.inlines);
  final int level; // 1..6
  final List<MdInline> inlines;
}

class MdParagraph extends MdBlock {
  MdParagraph(this.inlines);
  final List<MdInline> inlines;
}

class MdCodeBlock extends MdBlock {
  MdCodeBlock(this.text, {this.language});
  final String text;
  final String? language;
}

class MdBlockquote extends MdBlock {
  MdBlockquote(this.blocks);
  final List<MdBlock> blocks;
}

class MdList extends MdBlock {
  MdList({required this.ordered, required this.items});
  final bool ordered;

  /// Each item is the inline content of one list line.
  final List<List<MdInline>> items;
}

abstract class MdInline {}

class MdText extends MdInline {
  MdText(this.text);
  final String text;
}

class MdEmphasis extends MdInline {
  MdEmphasis(this.children, {required this.strong});
  final List<MdInline> children;
  final bool strong; // true = bold, false = italic
}

class MdCodeSpan extends MdInline {
  MdCodeSpan(this.text);
  final String text;
}

class MdLink extends MdInline {
  MdLink({required this.text, required this.href});
  final String text;
  final String href;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class Markdown {
  const Markdown._();

  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _ulItem = RegExp(r'^[-*+]\s+(.*)$');
  static final RegExp _olItem = RegExp(r'^\d+\.\s+(.*)$');
  static final RegExp _fence = RegExp(r'^```(.*)$');

  /// Parse [source] into a list of blocks.
  static List<MdBlock> parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final blocks = <MdBlock>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Fenced code block.
      final fence = _fence.firstMatch(line);
      if (fence != null) {
        final lang = fence.group(1)!.trim();
        final buf = <String>[];
        i++;
        while (i < lines.length && !_fence.hasMatch(lines[i])) {
          buf.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // consume closing fence
        blocks.add(MdCodeBlock(buf.join('\n'), language: lang.isEmpty ? null : lang));
        continue;
      }

      // Heading.
      final h = _heading.firstMatch(line);
      if (h != null) {
        blocks.add(MdHeading(h.group(1)!.length, parseInlines(h.group(2)!.trim())));
        i++;
        continue;
      }

      // Blockquote: gather consecutive '>' lines, recurse.
      if (line.startsWith('>')) {
        final buf = <String>[];
        while (i < lines.length && lines[i].startsWith('>')) {
          buf.add(lines[i].replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        blocks.add(MdBlockquote(parse(buf.join('\n'))));
        continue;
      }

      // Lists: gather consecutive items of the same kind.
      if (_ulItem.hasMatch(line) || _olItem.hasMatch(line)) {
        final ordered = _olItem.hasMatch(line);
        final pattern = ordered ? _olItem : _ulItem;
        final items = <List<MdInline>>[];
        while (i < lines.length && pattern.hasMatch(lines[i])) {
          items.add(parseInlines(pattern.firstMatch(lines[i])!.group(1)!));
          i++;
        }
        blocks.add(MdList(ordered: ordered, items: items));
        continue;
      }

      // Paragraph: consecutive non-blank, non-structural lines.
      final para = <String>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !_heading.hasMatch(lines[i]) &&
          !_fence.hasMatch(lines[i]) &&
          !lines[i].startsWith('>') &&
          !_ulItem.hasMatch(lines[i]) &&
          !_olItem.hasMatch(lines[i])) {
        para.add(lines[i]);
        i++;
      }
      blocks.add(MdParagraph(parseInlines(para.join('\n'))));
    }

    return blocks;
  }

  /// Parse inline markup within a single text run.
  static List<MdInline> parseInlines(String text) {
    final out = <MdInline>[];
    final buf = StringBuffer();
    var i = 0;
    final n = text.length;

    void flush() {
      if (buf.isNotEmpty) {
        out.add(MdText(buf.toString()));
        buf.clear();
      }
    }

    while (i < n) {
      final c = text[i];

      // Backslash escape: next char is literal.
      if (c == r'\' && i + 1 < n) {
        buf.write(text[i + 1]);
        i += 2;
        continue;
      }

      // Code span: `...`
      if (c == '`') {
        final end = text.indexOf('`', i + 1);
        if (end > i) {
          flush();
          out.add(MdCodeSpan(text.substring(i + 1, end)));
          i = end + 1;
          continue;
        }
      }

      // Link: [text](href)
      if (c == '[') {
        final close = text.indexOf(']', i + 1);
        if (close > i && close + 1 < n && text[close + 1] == '(') {
          final paren = text.indexOf(')', close + 2);
          if (paren > close) {
            flush();
            out.add(MdLink(
              text: text.substring(i + 1, close),
              href: text.substring(close + 2, paren),
            ),);
            i = paren + 1;
            continue;
          }
        }
      }

      // Strong: ** or __
      final strongDelim = _matchDelim(text, i, '**') ?? _matchDelim(text, i, '__');
      if (strongDelim != null) {
        final end = text.indexOf(strongDelim, i + 2);
        if (end > i) {
          flush();
          out.add(MdEmphasis(parseInlines(text.substring(i + 2, end)), strong: true));
          i = end + 2;
          continue;
        }
      }

      // Emphasis: * or _
      if (c == '*' || c == '_') {
        final end = text.indexOf(c, i + 1);
        if (end > i) {
          flush();
          out.add(MdEmphasis(parseInlines(text.substring(i + 1, end)), strong: false));
          i = end + 1;
          continue;
        }
      }

      // Autolink: bare http(s):// URL.
      if ((text.startsWith('http://', i) || text.startsWith('https://', i))) {
        final m = RegExp(r'^https?://[^\s)<>\]]+').firstMatch(text.substring(i));
        if (m != null) {
          flush();
          final url = m.group(0)!;
          out.add(MdLink(text: url, href: url));
          i += url.length;
          continue;
        }
      }

      buf.write(c);
      i++;
    }

    flush();
    return out;
  }

  /// Returns [delim] if [text] has it at [i] (and it's not immediately followed
  /// by whitespace, so `** ` isn't treated as an opener), else null.
  static String? _matchDelim(String text, int i, String delim) {
    if (!text.startsWith(delim, i)) return null;
    final after = i + delim.length;
    if (after >= text.length || text[after] == ' ') return null;
    return delim;
  }

  /// Convenience: extract every link href in document order (for "open URLs in
  /// notes" affordances).
  static List<String> extractLinks(String source) {
    final links = <String>[];
    void walkInline(List<MdInline> inlines) {
      for (final node in inlines) {
        if (node is MdLink) {
          links.add(node.href);
        } else if (node is MdEmphasis) {
          walkInline(node.children);
        }
      }
    }

    void walkBlock(List<MdBlock> blocks) {
      for (final b in blocks) {
        if (b is MdHeading) walkInline(b.inlines);
        if (b is MdParagraph) walkInline(b.inlines);
        if (b is MdList) {
          for (final item in b.items) {
            walkInline(item);
          }
        }
        if (b is MdBlockquote) walkBlock(b.blocks);
      }
    }

    walkBlock(parse(source));
    return links;
  }
}
