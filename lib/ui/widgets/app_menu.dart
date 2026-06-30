// dgvault — macOS application menu bar.
//
// MUST be a single PlatformMenuBar for the whole app (Flutter allows only one at
// a time — two instances assert). So it lives at the app root, always mounted,
// and routes the Vault commands through controller hooks the VaultScreen
// registers while it is on screen. ⌘ key-equivalents declared here are processed
// by AppKit before Flutter, so they work regardless of focus and override the
// default menu's conflicting items (⌘G "Find Next", ⌘C "Copy").
//
// No-op on non-macOS (those use Ctrl via CallbackShortcuts).

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/file_service.dart';
import '../state/vault_controller.dart';

Widget appMenuBar({
  required VaultController controller,
  required Widget child,
  VoidCallback? onAbout,
}) {
  if (defaultTargetPlatform != TargetPlatform.macOS) return child;
  return PlatformMenuBar(
    menus: [
      PlatformMenu(
        label: 'dgvault',
        menus: [
          PlatformMenuItem(label: 'About dgvault', onSelected: onAbout),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.quit,
          ),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItem(
            label: 'Open…',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
            onSelected: () async {
              final p = await VaultFiles.pickOpen();
              if (p != null) await controller.openFile(p);
            },
          ),
          PlatformMenuItem(
            label: 'Save',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
            onSelected: () {
              if (controller.status == VaultStatus.unlocked) controller.save();
            },
          ),
          PlatformMenuItem(
            label: 'Close',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
            onSelected: controller.close,
          ),
        ],
      ),
      PlatformMenu(
        label: 'Vault',
        menus: [
          PlatformMenuItem(
            label: 'Generate Password',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyG, meta: true),
            onSelected: () => controller.onGenerate?.call(),
          ),
          PlatformMenuItem(
            label: 'Copy Password',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
            onSelected: () => controller.onCopyPassword?.call(),
          ),
          PlatformMenuItem(
            label: 'Lock Vault',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyL, meta: true),
            onSelected: () {
              if (controller.status == VaultStatus.unlocked) controller.lock();
            },
          ),
        ],
      ),
      const PlatformMenu(
        label: 'Window',
        menus: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
        ],
      ),
    ],
    child: child,
  );
}
