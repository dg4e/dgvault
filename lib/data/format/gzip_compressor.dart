// dgvault — gzip compressor for the KDBX inner payload (CompressionFlags=1).
//
// KDBX stores the inner XML gzip-compressed (RFC 1952). This lives in the data
// layer because it uses `dart:io`'s GZipCodec; `lib/core` stays platform-neutral
// and depends only on the [Compressor] interface.

import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/format/kdbx_file.dart';

class GzipCompressor implements Compressor {
  const GzipCompressor();

  static final GZipCodec _codec = GZipCodec();

  @override
  Uint8List compress(Uint8List data) =>
      Uint8List.fromList(_codec.encode(data));

  @override
  Uint8List decompress(Uint8List data) =>
      Uint8List.fromList(_codec.decode(data));
}
