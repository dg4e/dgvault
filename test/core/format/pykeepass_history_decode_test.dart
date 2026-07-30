// Does dgvault's decoder flatten REAL KeePass history (produced by pykeepass)
// into sibling entries? The file has 1 live "paypal" + 5 nested <History>.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('real KeePass (pykeepass) KDBX4 history stays nested, not flattened',
      () async {
    final bytes =
        await File('test/fixtures/kdbx/hist_v4_pykeepass.kdbx').readAsBytes();
    final codec = KdbxCodec(
      bodyCipher: Kdbx4BodyCipher(kdf: const Argon2KeyDerivation()),
      compressor: const GzipCompressor(),
    );
    final db = await codec.read(
      Uint8List.fromList(bytes),
      CompositeCredential(password: Uint8List.fromList(utf8.encode('pw'))),
    );
    final live = db.root.allEntries.where((e) => e.title == 'paypal').toList();
    // ignore: avoid_print
    print('DGVAULT sees ${live.length} live paypal; '
        'history=${live.isNotEmpty ? live.first.history.length : "n/a"}');
    expect(live.length, 1, reason: 'flattened history into siblings!');
    expect(live.first.history.length, 5);
  });
}
