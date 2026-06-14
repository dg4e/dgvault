// dgvault — KDBX4 reader/writer pipeline orchestrator.
//
// Ties the format pieces together into the full read/write flow:
//
//   write:  Database --KeePassXml--> XML --compress--> inner
//                                    --KdbxBodyCipher.encrypt--> body
//           file = KdbxHeader.serialize() ++ body
//
//   read:   header = KdbxHeader.read(file); body = file[header.length:]
//           inner = KdbxBodyCipher.decrypt(body) --decompress--> XML
//           Database = KeePassXml.decode(XML)
//
// Cryptography and compression are **injected**, so this orchestrator is pure,
// platform-agnostic, and testable end-to-end with stub implementations. The
// real KDF→cipher→HMAC body transform (Argon2 + AES/ChaCha, toolchain-gated)
// implements [KdbxBodyCipher]; real gzip implements [Compressor] in the data
// layer. When those drop in, this pipeline reads/writes genuine `.kdbx` files
// with no structural changes.

import 'dart:convert';
import 'dart:typed_data';

import '../crypto/key_derivation.dart';
import '../model/database.dart';
import 'kdbx_header.dart';
import 'keepass_xml.dart';

/// Compresses/decompresses the inner XML payload (KDBX CompressionFlags).
abstract interface class Compressor {
  Uint8List compress(Uint8List data);
  Uint8List decompress(Uint8List data);
}

/// No-op compressor — corresponds to KDBX CompressionFlags=0 (no compression).
/// Real gzip (CompressionFlags=1) is provided by the data/platform layer.
class IdentityCompressor implements Compressor {
  const IdentityCompressor();
  @override
  Uint8List compress(Uint8List data) => data;
  @override
  Uint8List decompress(Uint8List data) => data;
}

/// Encrypts/decrypts the KDBX body (everything after the outer header).
///
/// A real implementation: derives the master key from [credential] + the
/// header's KDF parameters, verifies the header HMAC, then HMAC-block-stream
/// decrypts and runs the AES/ChaCha cipher — all using vetted crypto libs.
abstract interface class KdbxBodyCipher {
  /// Produces the encrypted body for [inner] (compressed XML) under [header].
  Future<Uint8List> encryptBody(
    KdbxHeader header,
    Uint8List inner,
    CompositeCredential credential,
  );

  /// Recovers the inner (compressed XML) bytes from [body]. Throws on a wrong
  /// credential / integrity failure.
  Future<Uint8List> decryptBody(
    KdbxHeader header,
    Uint8List body,
    CompositeCredential credential,
  );
}

class KdbxCodec {
  KdbxCodec({
    required this.bodyCipher,
    Compressor compressor = const IdentityCompressor(),
    KeePassXml xml = const KeePassXml(),
  })  : _compressor = compressor,
        _xml = xml;

  final KdbxBodyCipher bodyCipher;
  final Compressor _compressor;
  final KeePassXml _xml;

  /// Serializes [db] into a KDBX byte stream using [header] (which carries the
  /// cipher, KDF parameters, master seed and IV prepared by the crypto layer).
  Future<Uint8List> write(
    Database db,
    KdbxHeader header,
    CompositeCredential credential,
  ) async {
    final xmlString = _xml.encode(db);
    var inner = Uint8List.fromList(utf8.encode(xmlString));
    if (header.compressed) inner = _compressor.compress(inner);
    final body = await bodyCipher.encryptBody(header, inner, credential);

    final out = BytesBuilder();
    out.add(header.serialize());
    out.add(body);
    return out.toBytes();
  }

  /// Parses a KDBX byte stream back into a [Database].
  Future<Database> read(Uint8List bytes, CompositeCredential credential) async {
    final header = KdbxHeader.read(bytes);
    final body = Uint8List.sublistView(bytes, header.length);
    var inner = await bodyCipher.decryptBody(header, body, credential);
    if (header.compressed) inner = _compressor.decompress(inner);
    return _xml.decode(utf8.decode(inner));
  }
}
