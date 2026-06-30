// dgvault — application entry point.

import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/app_info.dart';
import 'ui/window_title.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppInfo(); // populate the version before the UI builds
  await initDesktopWindow(); // desktop title bar = "dgvault v0.1.0" (no-op elsewhere)
  // Windows/Linux forward the launched file as a command-line argument (file
  // association → `dgvault path.kdbx`). macOS/iOS/Android deliver it through the
  // open-file MethodChannel instead.
  runApp(DgvaultApp(initialFile: _initialFileArg(args)));
}

/// The first existing `.kdbx` path among the desktop command-line arguments.
String? _initialFileArg(List<String> args) {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    return null;
  }
  for (final a in args) {
    if (a.toLowerCase().endsWith('.kdbx') && File(a).existsSync()) return a;
  }
  return null;
}
