// dgvault — Android Storage Access Framework bridge.
//
// Opening/creating a vault through SAF yields a content:// URI with PERSISTABLE
// read/write permission, so edits can be written straight back to the original
// file the user chose (no local copy). The native side (MainActivity) runs the
// document pickers and reads/writes via the content resolver.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OpenedDocument {
  const OpenedDocument(this.uri, this.name, this.bytes);
  final String uri; // content:// (used as the vault "path")
  final String name; // display name for the UI
  final Uint8List bytes;
}

class CreatedDocument {
  const CreatedDocument(this.uri, this.name);
  final String uri;
  final String name;
}

class Documents {
  static const MethodChannel _ch = MethodChannel('dgvault/documents');

  /// SAF is Android-only; other platforms use filesystem paths.
  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  /// A location that must be read/written through SAF rather than dart:io.
  static bool isDocumentUri(String location) =>
      location.startsWith('content://');

  /// Prompt the user to pick an existing document (read/write). Null if
  /// cancelled.
  static Future<OpenedDocument?> pickOpen() async {
    final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('pickOpen');
    final bytes = r?['bytes'];
    if (r == null || bytes is! Uint8List) return null;
    return OpenedDocument(
        r['uri'] as String, r['name'] as String? ?? 'vault.kdbx', bytes,);
  }

  /// Prompt the user to choose a location + name for a new document.
  static Future<CreatedDocument?> pickCreate(String suggestedName) async {
    final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'pickCreate', {'name': suggestedName},);
    if (r == null || r['uri'] == null) return null;
    return CreatedDocument(
        r['uri'] as String, r['name'] as String? ?? suggestedName,);
  }

  static Future<Uint8List?> read(String uri) =>
      _ch.invokeMethod<Uint8List>('read', {'uri': uri});

  static Future<void> write(String uri, Uint8List bytes) =>
      _ch.invokeMethod<void>('write', {'uri': uri, 'bytes': bytes});
}
