// dgvault — app identity used by the title bar and the About cracktro.
//
// The version is read from the platform package metadata at startup (which
// Flutter derives from `version:` in pubspec.yaml), so it stays in sync
// automatically. Call [loadAppInfo] once in main() before runApp.

import 'package:package_info_plus/package_info_plus.dart';

const String kAppName = 'dgvault';
const String kAppCopyright = '(c)2026 digital gangster enterprises, llc';
const String kAppAuthors = 'written by ytcracker and clord';

String _version = '0.0.0'; // replaced by loadAppInfo() at startup

/// The running app's version (e.g. "0.1.0"), from the platform bundle.
String get appVersion => _version;

/// "dgvault v0.1.0"
String get appTitle => '$kAppName v$_version';

/// Read the version from the platform package metadata. Safe to call more than
/// once; falls back to the existing value if the lookup fails.
Future<void> loadAppInfo() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) _version = info.version;
  } catch (_) {
    // Keep the fallback if package metadata isn't available.
  }
}
