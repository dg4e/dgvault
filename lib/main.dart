// dgvault — application entry point.

import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/app_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppInfo(); // populate the version before the UI builds
  runApp(const DgvaultApp());
}
