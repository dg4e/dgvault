// dgvault — application entry point.

import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/app_info.dart';
import 'ui/window_title.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppInfo(); // populate the version before the UI builds
  await initDesktopWindow(); // desktop title bar = "dgvault v0.1.0" (no-op elsewhere)
  runApp(const DgvaultApp());
}
