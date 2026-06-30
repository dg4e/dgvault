// dgvault — receive ".kdbx opened with dgvault" events from the OS.
//
// Each platform's native runner declares dgvault as a handler for .kdbx files
// (Info.plist document types / Android intent-filter / desktop argv), reads the
// opened file's bytes, and delivers them here over a MethodChannel:
//   • cold start  — native stashes the file; Flutter pulls it via getInitialFile
//   • while running — native pushes it via the openFile call
// The bytes (not a path) are passed so Android content:// URIs and iOS
// security-scoped URLs work uniformly; an optional path lets desktop Save back.

import 'package:flutter/services.dart';

import 'vault_controller.dart';

class OpenFileChannel {
  OpenFileChannel(this.controller);

  static const MethodChannel _channel = MethodChannel('dgvault/open_file');
  final VaultController controller;

  /// Wire the handler and check whether the app was launched by opening a file.
  Future<void> start() async {
    _channel.setMethodCallHandler(_onCall);
    try {
      final initial = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getInitialFile',
      );
      if (initial != null) _load(initial);
    } on MissingPluginException {
      // Platform without the native side wired (e.g. web) — nothing to do.
    } catch (_) {
      // Never let a bad launch payload crash startup.
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'openFile' && call.arguments is Map) {
      _load(call.arguments as Map<dynamic, dynamic>);
    }
    return null;
  }

  void _load(Map<dynamic, dynamic> data) {
    final name = (data['name'] as String?) ?? 'vault.kdbx';
    final path = data['path'] as String?;
    final bytes = data['bytes'];
    if (bytes is Uint8List) {
      controller.loadBytes(bytes, name: name, path: path);
    } else if (path != null) {
      controller.openFile(path);
    }
  }
}
