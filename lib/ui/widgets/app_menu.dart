// dgvault — macOS application menu bar (always present so the menu is never
// empty, and so ⌘ commands are real menu key-equivalents that AppKit routes
// reliably, independent of Flutter focus).
//
// On non-macOS platforms this is a no-op passthrough (those use Ctrl shortcuts
// via CallbackShortcuts instead).

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

Widget appMenuBar({
  required Widget child,
  List<PlatformMenu> appMenus = const [],
}) {
  if (defaultTargetPlatform != TargetPlatform.macOS) return child;
  return PlatformMenuBar(
    menus: [
      const PlatformMenu(
        label: 'dgvault',
        menus: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ],
      ),
      ...appMenus,
      const PlatformMenu(
        label: 'Window',
        menus: [
          PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
        ],
      ),
    ],
    child: child,
  );
}
