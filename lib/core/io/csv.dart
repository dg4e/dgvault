// dgvault — RFC 4180 CSV codec.
//
// Pure Dart, no packages. Handles quoted fields, doubled-quote escaping,
// embedded commas/newlines inside quotes, and both LF and CRLF record
// separators. Used by the import/export feature; kept in `core` so it is
// platform-agnostic and unit-testable.

class CsvCodec {
  const CsvCodec({this.delimiter = ',', this.eol = '\r\n'});

  final String delimiter;

  /// Line ending used by [encode]. Decoding accepts LF, CRLF, or lone CR.
  final String eol;

  /// Parse [input] into a list of records, each a list of field strings.
  /// Returns an empty list for empty input.
  List<List<String>> decode(String input) {
    if (input.isEmpty) return <List<String>>[];
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    final n = input.length;
    var i = 0;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    while (i < n) {
      final c = input[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < n && input[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.write(c);
        i++;
        continue;
      }
      if (c == '"') {
        inQuotes = true;
        i++;
        continue;
      }
      if (c == delimiter) {
        endField();
        i++;
        continue;
      }
      if (c == '\r') {
        endRow();
        if (i + 1 < n && input[i + 1] == '\n') {
          i += 2;
        } else {
          i++;
        }
        continue;
      }
      if (c == '\n') {
        endRow();
        i++;
        continue;
      }
      field.write(c);
      i++;
    }

    // Flush the trailing field/row. A single empty field produced solely by a
    // trailing newline is dropped so files don't gain a phantom blank record.
    endField();
    if (!(row.length == 1 && row[0].isEmpty && rows.isNotEmpty)) {
      rows.add(row);
    }
    return rows;
  }

  /// Serialize [rows] to a CSV string using [delimiter]/[eol], quoting fields
  /// that contain the delimiter, a quote, or a line break.
  String encode(List<List<String>> rows) =>
      rows.map((r) => r.map(_encodeField).join(delimiter)).join(eol);

  String _encodeField(String f) {
    final needsQuote = f.contains('"') ||
        f.contains(delimiter) ||
        f.contains('\n') ||
        f.contains('\r');
    if (!needsQuote) return f;
    return '"${f.replaceAll('"', '""')}"';
  }
}
