// dgvault — native open/save file pickers (file_picker plugin).

import 'package:file_picker/file_picker.dart';

class VaultFiles {
  /// Pick an existing `.kdbx` file to open. Returns its path, or null if
  /// cancelled.
  static Future<String?> pickOpen() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open KDBX vault',
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
    );
    return result?.files.single.path;
  }

  /// Pick a location for a new `.kdbx` file. Returns the path, or null.
  static Future<String?> pickNew() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Create new vault',
      fileName: 'vault.kdbx',
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
    );
    if (path == null) return null;
    return path.endsWith('.kdbx') ? path : '$path.kdbx';
  }
}
