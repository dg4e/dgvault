// dgvault — file access.
//
// Desktop uses native open/save pickers and edits files in place. Mobile keeps
// vaults in an app-managed "vaults" folder (the app documents directory): New
// creates there, Open imports a copy there, and both get a real writable path
// so Save persists. A managed-vaults list lets you reopen them (the system
// picker can't browse app-private storage).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class VaultFiles {
  static bool get isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // ---- native pickers ------------------------------------------------------

  /// Pick an existing `.kdbx`. Mobile can't filter by the custom extension, so
  /// pick "any" there (the KDBX header check on load rejects non-vault files).
  static Future<String?> pickOpen() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open KDBX vault',
      type: isMobile ? FileType.any : FileType.custom,
      allowedExtensions: isMobile ? null : ['kdbx'],
    );
    return result?.files.single.path;
  }

  /// Desktop: pick a save location for a new `.kdbx`. (Mobile uses the managed
  /// vaults folder instead — see [newManagedVaultPath].)
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

  // ---- app-managed vaults (mobile) -----------------------------------------

  /// The app-private folder holding managed vaults (created on first use).
  static Future<Directory> vaultsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/vaults');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// The managed `.kdbx` files, sorted by name.
  static Future<List<File>> listManagedVaults() async {
    final dir = await vaultsDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.kdbx'))
        .toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return files;
  }

  /// A unique writable path for a NEW managed vault named [name].
  static Future<String> newManagedVaultPath(String name) async =>
      uniqueVaultPath(await vaultsDir(), name);

  /// Write [bytes] into the managed folder as `<name>.kdbx` (overwriting an
  /// existing managed copy of the same name) and return its path.
  static Future<String> importBytes(Uint8List bytes, String name) async {
    final dir = await vaultsDir();
    final path = '${dir.path}/${sanitizeVaultName(_stripKdbx(name))}.kdbx';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Delete a managed vault file.
  static Future<void> deleteManaged(String path) => File(path).delete();

  // ---- pure helpers (unit-tested) ------------------------------------------

  /// Filesystem-safe base name (no extension), never empty.
  static String sanitizeVaultName(String name) {
    final safe =
        _stripKdbx(name).trim().replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    return safe.isEmpty ? 'vault' : safe;
  }

  /// A `.kdbx` path in [dir] that doesn't collide with an existing file.
  static String uniqueVaultPath(Directory dir, String name) {
    final base = sanitizeVaultName(name);
    var candidate = '$base.kdbx';
    var n = 1;
    while (File('${dir.path}/$candidate').existsSync()) {
      candidate = '$base ($n).kdbx';
      n++;
    }
    return '${dir.path}/$candidate';
  }

  static String _stripKdbx(String name) => name.toLowerCase().endsWith('.kdbx')
      ? name.substring(0, name.length - 5)
      : name;
}
