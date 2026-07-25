// dgvault — mobile document bridge (in-place open/save).
//
// Opening or creating a vault through the OS document picker yields a location
// token with PERSISTABLE read/write access, so edits are written straight back
// to the original file the user chose (no local copy):
//   • Android — a SAF content:// URI (native: MainActivity, via the content
//     resolver with takePersistableUriPermission).
//   • iOS — a security-scoped bookmark encoded as `bookmark:<base64>` (native:
//     DocumentPickerBridge, via UIDocumentPickerViewController + NSFileCoordinator).
// Both platforms speak the same MethodChannel; the token is opaque to Dart and
// is stored as the vault "path".

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OpenedDocument {
  const OpenedDocument(this.uri, this.name, this.bytes);
  final String uri; // content:// (Android) or bookmark:… (iOS) — the vault "path"
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

  /// The native document picker drives open/new (Android SAF / iOS). Desktop
  /// keeps using file_selector + filesystem paths.
  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Sandboxed macOS can't reopen a file by raw path in a later session (the
  /// open-panel grant doesn't persist) — a "recent" needs a security-scoped
  /// bookmark. [bookmark] converts a currently-accessible path into one.
  static bool get bookmarksRecents =>
      defaultTargetPlatform == TargetPlatform.macOS;

  /// A location that must be read/written through the bridge rather than
  /// dart:io — an Android SAF URI or an iOS/macOS security-scoped bookmark.
  static bool isDocumentUri(String location) =>
      location.startsWith('content://') || location.startsWith('bookmark:');

  /// Create a persistable security-scoped bookmark for [path] (macOS). Returns
  /// a `bookmark:` token, or null if the platform/OS couldn't make one (the
  /// caller then falls back to the raw path).
  static Future<String?> bookmark(String path) =>
      _ch.invokeMethod<String>('bookmark', {'path': path});

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
