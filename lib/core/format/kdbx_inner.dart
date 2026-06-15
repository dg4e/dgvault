// dgvault — KDBX4 inner header + inner random stream (protected values).
//
// Inside the decrypted+decompressed body sits an inner header (TLV) followed by
// the XML. The inner header carries the InnerRandomStreamID + key used to
// encrypt every `Protected="True"` value: those values are stored as
// base64(stream-XOR(plaintext)), the stream advancing across all protected
// values in document order. KeePassXC uses ChaCha20; KeePass 2.x used Salsa20.
//
// No hand-rolled crypto — the stream is pointycastle's ChaCha20/Salsa20; this
// file owns only the inner-header framing and the document-order walk.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;
import 'package:xml/xml.dart';

class KdbxInnerFormatException implements Exception {
  KdbxInnerFormatException(this.message);
  final String message;
  @override
  String toString() => 'KdbxInnerFormatException: $message';
}

/// Inner random stream cipher ids (KDBX inner header field 1).
class InnerStreamId {
  static const int none = 0;
  static const int arcFourVariant = 1; // deprecated, unsupported
  static const int salsa20 = 2; // KeePass 2.x
  static const int chaCha20 = 3; // KeePassXC default
}

/// The KDBX4 inner header: the protected-value stream id/key + inline binaries.
class KdbxInnerHeader {
  KdbxInnerHeader({
    required this.streamId,
    required this.streamKey,
    List<Uint8List>? binaries,
  }) : binaries = binaries ?? <Uint8List>[];

  final int streamId;
  final Uint8List streamKey;

  /// Inline binary contents (each prefixed in the file by a 1-byte flags field).
  final List<Uint8List> binaries;

  static const int _fEnd = 0;
  static const int _fStreamId = 1;
  static const int _fStreamKey = 2;
  static const int _fBinary = 3;

  /// Parse the inner header from [payload]; returns the header and the XML bytes
  /// that follow it.
  static (KdbxInnerHeader, Uint8List) parse(Uint8List payload) {
    final bd = ByteData.sublistView(payload);
    var offset = 0;
    int? streamId;
    Uint8List? streamKey;
    final binaries = <Uint8List>[];

    while (true) {
      if (offset + 5 > payload.length) {
        throw KdbxInnerFormatException('truncated inner header');
      }
      final id = bd.getUint8(offset);
      offset += 1;
      final len = bd.getUint32(offset, Endian.little);
      offset += 4;
      if (offset + len > payload.length) {
        throw KdbxInnerFormatException('inner header field overruns payload');
      }
      final data = Uint8List.sublistView(payload, offset, offset + len);
      offset += len;

      switch (id) {
        case _fEnd:
          final header = KdbxInnerHeader(
            streamId: streamId ?? InnerStreamId.none,
            streamKey: streamKey ?? Uint8List(0),
            binaries: binaries,
          );
          return (header, Uint8List.sublistView(payload, offset));
        case _fStreamId:
          streamId = ByteData.sublistView(data).getUint32(0, Endian.little);
        case _fStreamKey:
          streamKey = Uint8List.fromList(data);
        case _fBinary:
          // First byte is flags (memory-protection); the rest is content.
          binaries.add(Uint8List.fromList(
              data.isEmpty ? data : data.sublist(1),),);
        default:
          break; // forward-compatible
      }
    }
  }

  /// Serialize the inner header (without the trailing XML).
  Uint8List serialize() {
    final out = BytesBuilder();
    void field(int id, Uint8List data) {
      out.addByte(id);
      out.add((ByteData(4)..setUint32(0, data.length, Endian.little))
          .buffer
          .asUint8List(),);
      out.add(data);
    }

    field(_fStreamId,
        (ByteData(4)..setUint32(0, streamId, Endian.little)).buffer.asUint8List(),);
    field(_fStreamKey, streamKey);
    for (final b in binaries) {
      field(_fBinary, Uint8List.fromList([0x00, ...b])); // flags=0 + content
    }
    field(_fEnd, Uint8List(0));
    return out.toBytes();
  }
}

/// The continuous keystream applied to protected values, in document order.
class InnerRandomStream {
  InnerRandomStream._(this._engine);

  final pc.StreamCipher _engine;

  factory InnerRandomStream.fromId(int streamId, Uint8List key) {
    switch (streamId) {
      case InnerStreamId.chaCha20:
        final mat = pc.SHA512Digest().process(key);
        final k = Uint8List.sublistView(mat, 0, 32);
        final iv = Uint8List.sublistView(mat, 32, 44);
        return InnerRandomStream._(pc.ChaCha7539Engine()
          ..init(true, pc.ParametersWithIV(pc.KeyParameter(k), iv)),);
      case InnerStreamId.salsa20:
        final k = pc.SHA256Digest().process(key);
        final iv = Uint8List.fromList(
            [0xE8, 0x30, 0x09, 0x4B, 0x97, 0x20, 0x5D, 0x2A],); // KeePass fixed IV
        return InnerRandomStream._(pc.Salsa20Engine()
          ..init(true, pc.ParametersWithIV(pc.KeyParameter(k), iv)),);
      default:
        throw KdbxInnerFormatException(
            'unsupported inner random stream id $streamId',);
    }
  }

  /// XOR [data] with the next len bytes of keystream (advances the stream).
  Uint8List crypt(Uint8List data) => _engine.process(data);
}

/// Decrypts every `Protected="True"` value in [xml] in document order, returning
/// XML with those values as plaintext (ready for [KeePassXml.decode]).
String unprotectXml(String xml, InnerRandomStream stream) =>
    _walkProtected(xml, (text) {
      final cipher = base64.decode(text.trim());
      return utf8.decode(stream.crypt(cipher));
    });

/// Inverse of [unprotectXml]: encrypts plaintext protected values to
/// base64(stream-XOR), for writing a KDBX body.
String protectXml(String xml, InnerRandomStream stream) =>
    _walkProtected(xml, (text) {
      final plain = Uint8List.fromList(utf8.encode(text));
      return base64.encode(stream.crypt(plain));
    });

String _walkProtected(String xml, String Function(String) transform) {
  final doc = XmlDocument.parse(xml);
  for (final el in doc.descendants.whereType<XmlElement>()) {
    if (el.name.local == 'Value' && el.getAttribute('Protected') == 'True') {
      final out = transform(el.innerText);
      el.children
        ..clear()
        ..add(XmlText(out));
    }
  }
  return doc.toXmlString();
}
