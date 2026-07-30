// Does dgvault's KDBX3 reader flatten history into siblings? Fixture: real v3.1
// with 1 live "paypal" + 12 nested <History> versions (pykeepass confirms 1+12).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/kdbx3_reader.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KDBX3 read keeps history nested (paypal appears once)', () async {
    final bytes = File('test/fixtures/kdbx/hist_v3.kdbx').readAsBytesSync();
    final db = await const Kdbx3Reader().read(
      Uint8List.fromList(bytes),
      CompositeCredential(
          password: Uint8List.fromList(utf8.encode('kdbx3pass')),),
      compressor: const GzipCompressor(),
    );
    final live = db.root.allEntries.where((e) => e.title == 'paypal').toList();
    // ignore: avoid_print
    print('DGVAULT KDBX3 read: ${live.length} live paypal; '
        'history=${live.isNotEmpty ? live.first.history.length : "n/a"}');
    expect(live.length, 1,
        reason: 'KDBX3 read flattened history into siblings',);
    expect(live.first.history.length, 12);
  });
}
