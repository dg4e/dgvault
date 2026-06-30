// dgvault — native open/save file pickers (file_picker plugin).

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

class VaultFiles {
  // Mobile file pickers can't filter by a custom ".kdbx" extension (the plugin
  // has no MIME/UTI mapping for it and throws), so pick "any" there — the KDBX
  // header check on load rejects non-vault files. Desktop keeps the .kdbx filter.
  static bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Pick an existing `.kdbx` file to open. Returns its path, or null if
  /// cancelled.
  static Future<String?> pickOpen() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open KDBX vault',
      type: _mobile ? FileType.any : FileType.custom,
      allowedExtensions: _mobile ? null : ['kdbx'],
    );
    return result?.files.single.path;
  }

  /// Pick a location for a new `.kdbx` file. Returns the path, or null.
  static Future<String?> pickNew() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Create new vault',
      fileName: 'vault.kdbx',
      type: _mobile ? FileType.any : FileType.custom,
      allowedExtensions: _mobile ? null : ['kdbx'],
    );
    if (path == null) return null;
    return path.endsWith('.kdbx') ? path : '$path.kdbx';
  }
}
