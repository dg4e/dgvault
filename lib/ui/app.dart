// dgvault — root app: owns the VaultController and routes between the landing,
// unlock, and vault screens.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_info.dart';
import 'screens/cracktro_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/vault_screen.dart';
import 'state/vault_controller.dart';
import 'theme/terminal_theme.dart';
import 'widgets/app_menu.dart';
import 'window_title.dart';

class DgvaultApp extends StatefulWidget {
  const DgvaultApp({super.key, this.controller});

  /// Inject a controller (tests); otherwise one is created.
  final VaultController? controller;

  @override
  State<DgvaultApp> createState() => _DgvaultAppState();
}

class _DgvaultAppState extends State<DgvaultApp> {
  late final VaultController _controller =
      widget.controller ?? VaultController();
  final _navKey = GlobalKey<NavigatorState>();

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
