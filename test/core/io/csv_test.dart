import 'package:dgvault/core/io/csv.dart';
import 'package:test/test.dart';

void main() {
  const csv = CsvCodec();

  group('decode', () {
    test('simple rows', () {
      expect(csv.decode('a,b,c\n1,2,3'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('quoted field containing the delimiter', () {
      expect(csv.decode('a,"b,c",d'), [
        ['a', 'b,c', 'd'],
      ]);
    });

    test('doubled quotes unescape to a single quote', () {
      expect(csv.decode('"she said ""hi"""'), [
        ['she said "hi"'],
      ]);
    });

    test('embedded newline inside quotes', () {
      expect(csv.decode('"line1\nline2",x'), [
        ['line1\nline2', 'x'],
      ]);
    });

    test('handles CRLF and lone LF', () {
      expect(csv.decode('a,b\r\nc,d\ne,f'), [
        ['a', 'b'],
        ['c', 'd'],
        ['e', 'f'],
      ]);
    });

    test('trailing newline does not create a blank record', () {
      expect(csv.decode('a,b\n'), [
        ['a', 'b'],
      ]);
    });

    test('empty input yields no rows', () {
      expect(csv.decode(''), isEmpty);
    });

    test('empty fields preserved', () {
      expect(csv.decode('a,,c'), [
        ['a', '', 'c'],
      ]);
    });
  });

  group('encode', () {
    test('quotes only fields that need it', () {
      final out = csv.encode([
        ['a', 'b,c', 'd"e', 'f\ng', 'plain'],
      ]);
      expect(out, 'a,"b,c","d""e","f\ng",plain');
    });
  });

  group('round trip', () {
    test('decode(encode(x)) == x for tricky data', () {
      final data = [
        ['Group', 'Title', 'Notes'],
        ['Bank/Personal', 'ACME, Inc', 'multi\nline "quoted"'],
        ['', 'Empty group', ''],
      ];
      expect(csv.decode(csv.encode(data)), data);
    });
  });
}
