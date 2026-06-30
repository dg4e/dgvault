// dgvault — root app: owns the VaultController and routes between the landing,
// unlock, and vault screens.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_info.dart';
import 'screens/cracktro_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/vault_screen.dart';
import 'state/open_file_channel.dart';
import 'state/vault_controller.dart';
import 'theme/terminal_theme.dart';
import 'widgets/app_menu.dart';
import 'widgets/auto_lock_gate.dart';
import 'window_title.dart';

class DgvaultApp extends StatefulWidget {
  const DgvaultApp({super.key, this.controller, this.initialFile});

  /// Inject a controller (tests); otherwise one is created.
  final VaultController? controller;

  /// A `.kdbx` path the app was launched with (Windows/Linux file association).
  final String? initialFile;

  @override
  State<DgvaultApp> createState() => _DgvaultAppState();
}

class _DgvaultAppState extends State<DgvaultApp> {
  late final VaultController _controller =
      widget.controller ?? VaultController();
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Handle a .kdbx that the OS opened with dgvault (file association).
    if (widget.controller == null) {
      OpenFileChannel(_controller).start(); // macOS/iOS/Android (channel)
      final initial = widget.initialFile; // Windows/Linux (command-line arg)
      if (initial != null) _controller.openFile(initial);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  // Triggered by the macOS "About dgvault" menu item; works on any screen.
  void _showAbout() {
    final ctx = _navKey.currentContext;
    if (ctx != null) showCracktro(ctx);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle, // dgvault v0.1.0
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: buildTerminalTheme(),
      // Wrap everything (screens + dialogs/sheets) so auto-lock sees activity
      // everywhere and can re-lock on idle / loss of focus.
      builder: (context, child) => AutoLockGate(
        controller: _controller,
        child: child ?? const SizedBox.shrink(),
      ),
      // Single, always-mounted menu bar (macOS) — Flutter allows only one
      // PlatformMenuBar at a time, so it lives here above the screen switch.
      home: appMenuBar(
        controller: _controller,
        onAbout: _showAbout,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            // Mirror the in-app header onto the native desktop title bar.
            unawaited(setWindowTitle(windowTitleFor(_controller.fileName)));
            switch (_controller.status) {
              case VaultStatus.noVault:
                return LandingScreen(controller: _controller);
              case VaultStatus.locked:
              case VaultStatus.unlocking:
                return UnlockScreen(controller: _controller);
              case VaultStatus.unlocked:
              case VaultStatus.saving:
                return VaultScreen(controller: _controller);
            }
          },
        ),
      ),
    );
  }
}
