import 'package:dgvault/core/markdown/markdown.dart';
import 'package:test/test.dart';

void main() {
  group('blocks', () {
    test('ATX heading captures level and inline text', () {
      final b = Markdown.parse('### Hello').single as MdHeading;
      expect(b.level, 3);
      expect((b.inlines.single as MdText).text, 'Hello');
    });

    test('fenced code block keeps content + language, no inline parsing', () {
      final blocks = Markdown.parse('```dart\nfinal x = **not bold**;\n```');
      final code = blocks.single as MdCodeBlock;
      expect(code.language, 'dart');
      expect(code.text, 'final x = **not bold**;');
    });

    test('blockquote recurses into inner blocks', () {
      final bq = Markdown.parse('> quoted line').single as MdBlockquote;
      expect(bq.blocks.single, isA<MdParagraph>());
      final p = bq.blocks.single as MdParagraph;
      expect((p.inlines.single as MdText).text, 'quoted line');
    });

    test('unordered list groups consecutive items', () {
      final list = Markdown.parse('- one\n- two\n- three').single as MdList;
      expect(list.ordered, isFalse);
      expect(list.items.length, 3);
      expect((list.items[1].single as MdText).text, 'two');
    });

    test('ordered list', () {
      final list = Markdown.parse('1. a\n2. b').single as MdList;
      expect(list.ordered, isTrue);
      expect(list.items.length, 2);
    });

    test('blank lines separate paragraphs', () {
      final blocks = Markdown.parse('para one\nstill one\n\npara two');
      expect(blocks.length, 2);
      expect(blocks.every((b) => b is MdParagraph), isTrue);
    });
  });

  group('inline', () {
    List<MdInline> inl(String s) =>
        (Markdown.parse(s).single as MdParagraph).inlines;

    test('bold and italic', () {
      final b = inl('**bold**').single as MdEmphasis;
      expect(b.strong, isTrue);
      expect((b.children.single as MdText).text, 'bold');

      final it = inl('*ital*').single as MdEmphasis;
      expect(it.strong, isFalse);
    });

    test('code span is literal (no nested parsing)', () {
      final c = inl('`a*b*c`').single as MdCodeSpan;
      expect(c.text, 'a*b*c');
    });

    test('explicit link', () {
      final l = inl('[site](https://x.io)').single as MdLink;
      expect(l.text, 'site');
      expect(l.href, 'https://x.io');
    });

    test('bare URL autolink stops at whitespace', () {
      final nodes = inl('go https://x.io/p?q=1 now');
      final link = nodes.firstWhere((n) => n is MdLink) as MdLink;
      expect(link.href, 'https://x.io/p?q=1');
    });

    test('backslash escapes a delimiter to literal text', () {
      final nodes = inl(r'\*not italic\*');
      expect((nodes.single as MdText).text, '*not italic*');
    });

    test('mixed inline run', () {
      final nodes = inl('a **b** c `d`');
      expect(nodes.length, 4); // "a ", bold, " c ", code
      expect(nodes[1], isA<MdEmphasis>());
      expect(nodes[3], isA<MdCodeSpan>());
    });
  });

  group('extractLinks', () {
    test('collects hrefs from paragraphs, lists, and blockquotes', () {
      const src = '[a](https://a.test)\n\n'
          '- item [b](https://b.test)\n\n'
          '> quote https://c.test';
      expect(Markdown.extractLinks(src),
          ['https://a.test', 'https://b.test', 'https://c.test'],);
    });
  });
}
