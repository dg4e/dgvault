// dgvault — gzip compressor for the KDBX inner payload (CompressionFlags=1).
//
// KDBX stores the inner XML gzip-compressed (RFC 1952). This lives in the data
// layer because it uses `dart:io`'s GZipCodec; `lib/core` stays platform-neutral
// and depends only on the [Compressor] interface.

import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/format/kdbx_file.dart';

class GzipCompressor implements Compressor {
  const GzipCompressor({this.maxDecompressedBytes = 256 * 1024 * 1024});

  /// Hard cap on decompressed output — defends against a "gzip bomb" embedded
  /// in an otherwise-valid vault expanding to gigabytes and exhausting memory.
  /// 256 MiB is far above any real KDBX inner XML.
  final int maxDecompressedBytes;

  static final GZipCodec _codec = GZipCodec();

  @override
  Uint8List compress(Uint8List data) =>
      Uint8List.fromList(_codec.encode(data));

  @override
  Uint8List decompress(Uint8List data) {
    final sink = _CappedSink(maxDecompressedBytes);
    final input = _codec.decoder.startChunkedConversion(sink);
    try {
      input.add(data);
      input.close();
    } on FormatException catch (e) {
      throw GzipException('not a valid gzip stream: ${e.message}');
    }
    return sink.bytes();
  }
}

/// Raised when decompression fails or exceeds [GzipCompressor.maxDecompressedBytes].
class GzipException implements Exception {
  GzipException(this.message);
  final String message;
  @override
  String toString() => 'GzipException: $message';
}

/// Accumulates decoded chunks, aborting once the running total exceeds [cap].
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.cap);
  final int cap;
  final BytesBuilder _out = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (_out.length + data.length > cap) {
      throw GzipException('decompressed output exceeds ${cap}B cap');
    }
    _out.add(data);
  }

  @override
  void close() {}

  Uint8List bytes() => _out.toBytes();
}
