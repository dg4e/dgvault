// dgvault — root app: owns the VaultController and routes between the landing,
// unlock, and vault screens.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart' show WindowListener;

import 'anim/fx.dart';
import 'app_info.dart';
import 'dev/demo_vault.dart';
import 'screens/cracktro_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/vault_screen.dart';
import 'state/documents.dart';
import 'state/open_file_channel.dart';
import 'state/recent_vaults.dart';
import 'widgets/privacy_gate.dart';
import 'widgets/terminal_widgets.dart' show clipboardService;
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

class _DgvaultAppState extends State<DgvaultApp> with WindowListener {
  late final VaultController _controller =
      widget.controller ?? VaultController();
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Load the persisted "screen effects" preference (default on).
    unawaited(Fx.instance.load());
    // Handle a .kdbx that the OS opened with dgvault (file association).
    if (widget.controller == null) {
      // Remember opened/created vaults for one-tap reopen on the landing screen.
      _controller.onVaultAccessed = _rememberRecent;
      // Wipe an auto-clearing clipboard secret when the vault locks.
      _controller.onLockClearClipboard = clipboardService.clearNow;
      // A manual lock with unsaved edits prompts save/discard/cancel rather than
      // silently discarding them.
      _controller.onManualLockWhileDirty = () => _resolveDirtyPrompt('lock');
      // Guard the desktop window close so quitting with unsaved edits prompts
      // the same save/discard/cancel choice instead of silently dropping them.
      addWindowListener(this);
      unawaited(setWindowPreventClose(true));
      OpenFileChannel(_controller).start(); // macOS/iOS/Android (channel)
      final initial = widget.initialFile; // Windows/Linux (command-line arg)
      if (initial != null) _controller.openFile(initial);
    }
    // Debug/dev hook: jump straight to the About cracktro on launch, so it can
    // be eyeballed on simulators where taps can't be scripted:
    //   flutter run --dart-define=DGVAULT_OPEN_ABOUT=true
    if (const bool.fromEnvironment('DGVAULT_OPEN_ABOUT')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showAbout());
    }
    // Same idea for store screenshots: seed a demo vault and stage a screen.
    //   flutter run --dart-define=DGVAULT_DEMO=vault|locked|detail|generator|settings
    const demoStage = String.fromEnvironment('DGVAULT_DEMO');
    if (demoStage.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => stageDemo(_controller, demoStage, _navKey),
      );
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      removeWindowListener(this);
      _controller.dispose();
    }
    super.dispose();
  }

  /// Native desktop window-close request. With prevent-close enabled the window
  /// won't close until we explicitly destroy it, so guard unsaved edits first.
  @override
  void onWindowClose() async {
    if (_controller.isDirty) {
      final proceed = await _resolveDirtyPrompt('quit');
      if (!proceed) return; // cancelled or save failed — keep the window open
    }
    await destroyWindow();
  }

  /// Record a just-opened vault as a recent. On sandboxed macOS a raw path
  /// can't be reopened next session, so convert it to a security-scoped
  /// bookmark first; on failure fall back to the raw path.
  Future<void> _rememberRecent(String location, String name) async {
    var loc = location;
    if (Documents.bookmarksRecents && !Documents.isDocumentUri(location)) {
      final token = await Documents.bookmark(location);
      if (token != null) loc = token;
    }
    await RecentVaults.remember(loc, name);
  }

  /// Prompt the user before an action ([actionVerb], e.g. "lock" or "quit")
  /// discards unsaved edits. Returns true to proceed (after saving, or on an
  /// explicit discard), false to cancel. If there is no writable location we
  /// can't save or discard blindly, so default to save-if-possible.
  Future<bool> _resolveDirtyPrompt(String actionVerb) async {
    final ctx = _navKey.currentContext;
    if (ctx == null) {
      // No UI available — save if we can, otherwise abort (never lose edits).
      if (_controller.path == null) return false;
      await _controller.save();
      return _controller.error == null;
    }
    final choice = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('unsaved changes'),
        content: Text(
          'you have unsaved edits. save before you $actionVerb, or discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop('cancel'),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop('discard'),
            child: const Text('discard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop('save'),
            child: Text('save & $actionVerb'),
          ),
        ],
      ),
    );
    switch (choice) {
      case 'save':
        if (_controller.path == null) return false; // nowhere to save → abort
        await _controller.save();
        return _controller.error == null;
      case 'discard':
        return true; // proceed with the action, dropping the edits
      default:
        return false; // cancel / dismissed
    }
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
      // everywhere and can re-lock on idle / loss of focus. PrivacyGate covers
      // the UI when the app backgrounds so the switcher/recents snapshot (iOS in
      // particular, which has no FLAG_SECURE) never captures vault contents.
      builder: (context, child) => PrivacyGate(
        child: AutoLockGate(
          controller: _controller,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      // Single, always-mounted menu bar (macOS) — Flutter allows only one
      // PlatformMenuBar at a time, so it lives here above the screen switch.
      home: appMenuBar(
        controller: _controller,
        onAbout: _showAbout,
        // Rebuild the whole tree when "screen effects" is toggled so the FX
        // helpers below pick up the new setting immediately.
        child: ValueListenableBuilder<bool>(
          valueListenable: Fx.instance.enabled,
          builder: (context, _, __) => ListenableBuilder(
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
      ),
    );
  }
}
