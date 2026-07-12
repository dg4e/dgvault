// dgvault — native OS window title control (desktop only).
//
// On macOS/Windows/Linux the title bar should mirror the in-app header:
// "dgvault v0.1.0" plus "— <filename>" once a vault is loaded. window_manager
// drives the native NSWindow / Win32 / GTK title; on mobile and web this is a
// no-op.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'app_info.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

// Only true after a successful initDesktopWindow(); guards setWindowTitle so
// widget tests (which never call main()) don't poke the uninitialized plugin.
bool _ready = false;
String? _lastTitle;

/// Initialize the window manager (desktop only) and set the initial title.
Future<void> initDesktopWindow() async {
  if (!_isDesktop) return;
  await windowManager.ensureInitialized();
  _ready = true;
  await setWindowTitle(appTitle);
}

/// The window/title-bar string for the current file (null → just the version).
String windowTitleFor(String? fileName) =>
    fileName == null ? appTitle : '$appTitle — $fileName';

/// Set the native window title (desktop only), skipping redundant updates.
Future<void> setWindowTitle(String title) async {
  if (!_ready || title == _lastTitle) return;
  _lastTitle = title;
  await windowManager.setTitle(title);
}

/// Prevent the native window from closing on its own so the app can intercept
/// the close and guard unsaved edits (desktop only; no-op elsewhere/pre-init).
Future<void> setWindowPreventClose(bool prevent) async {
  if (!_ready) return;
  await windowManager.setPreventClose(prevent);
}

/// Register/unregister a native window listener (desktop only).
void addWindowListener(WindowListener listener) {
  if (!_isDesktop) return;
  windowManager.addListener(listener);
}

void removeWindowListener(WindowListener listener) {
  if (!_isDesktop) return;
  windowManager.removeListener(listener);
}

/// Actually close the window once our pre-close checks pass (desktop only).
Future<void> destroyWindow() async {
  if (!_ready) return;
  await windowManager.destroy();
}
