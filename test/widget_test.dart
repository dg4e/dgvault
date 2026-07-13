// Widget smoke tests for the terminal UI shell.

import 'package:dgvault/ui/app.dart';
import 'package:dgvault/ui/app_info.dart';
import 'package:dgvault/ui/state/clipboard_service.dart';
import 'package:dgvault/ui/screens/cracktro_screen.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:dgvault/ui/theme/terminal_theme.dart';
import 'package:dgvault/ui/widgets/folder_tree.dart';
import 'package:dgvault/ui/widgets/terminal_widgets.dart' show clipboardService;
import 'package:dgvault/ui/window_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'ui/test_vault.dart';

Future<VaultController> _unlocked(WidgetTester tester) async {
  final c = VaultController();
  c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
  await c.unlock(testVaultPassword);
  await tester.pumpWidget(DgvaultApp(controller: c));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

bool _searchHasFocus(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  setUp(() async {
    // Feed package_info_plus a known version so appTitle resolves in tests.
    PackageInfo.setMockInitialValues(
      appName: 'dgvault',
      packageName: 'com.dgvault.dgvault',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await loadAppInfo();
  });

  testWidgets('landing shows open/new when no vault is loaded', (tester) async {
    await tester.pumpWidget(DgvaultApp(controller: VaultController()));
    await tester.pump();
    expect(find.text('[ OPEN .KDBX ]'), findsOneWidget);
    expect(find.text('[ NEW VAULT ]'), findsOneWidget);
  });

  testWidgets('a loaded file shows the unlock prompt', (tester) async {
    final c = VaultController();
    c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
    await tester.pumpWidget(DgvaultApp(controller: c));
    await tester.pump();

    expect(find.text('test.kdbx'), findsOneWidget); // filename shown
    expect(find.text('[ UNLOCK ]'), findsOneWidget);
  });

  testWidgets('unlocked state renders the vault with entries', (tester) async {
    await _unlocked(tester);
    // 'GitHub' shows in the list and (two-pane) the detail header.
    expect(find.text('GitHub'), findsWidgets);
    expect(find.text('UNLOCKED'), findsOneWidget); // status bar mode
  });

  testWidgets('^L (Ctrl+L) locks the vault', (tester) async {
    final c = await _unlocked(tester);
    expect(c.status, VaultStatus.unlocked);

    await _ctrl(tester, LogicalKeyboardKey.keyL);

    expect(c.status, VaultStatus.locked);
    expect(find.text('[ UNLOCK ]'), findsOneWidget);
  });

  testWidgets('^G (Ctrl+G) opens the password generator', (tester) async {
    await _unlocked(tester);
    expect(find.text('// PASSWORD GENERATOR'), findsNothing);

    await _ctrl(tester, LogicalKeyboardKey.keyG);

    expect(find.text('// PASSWORD GENERATOR'), findsOneWidget);
  });

  testWidgets('/ focuses the search field', (tester) async {
    await _unlocked(tester);
    expect(_searchHasFocus(tester), isFalse);

    await _key(tester, LogicalKeyboardKey.slash);

    expect(_searchHasFocus(tester), isTrue);
  });

  testWidgets('Esc clears an active search, then locks', (tester) async {
    final c = await _unlocked(tester);

    await tester.enterText(find.byType(EditableText), 'github');
    await tester.pumpAndSettle();
    expect(find.text('Proton Mail'), findsNothing); // filtered out

    await _key(tester, LogicalKeyboardKey.escape); // first esc clears search
    expect(find.text('Proton Mail'), findsWidgets);
    expect(c.status, VaultStatus.unlocked);

    await _key(tester, LogicalKeyboardKey.escape); // second esc locks
    expect(c.status, VaultStatus.locked);
  });

  testWidgets('arrow down moves the selection to the next entry', (tester) async {
    await _unlocked(tester);
    // Default selection is the first entry → its URL shows in the detail pane.
    expect(find.text('https://github.com'), findsOneWidget);

    await _key(tester, LogicalKeyboardKey.arrowDown);

    expect(find.text('https://github.com'), findsNothing);
    expect(find.text('https://proton.me'), findsOneWidget);
  });

  testWidgets('title bar shows version + filename; About opens the cracktro',
      (tester) async {
    // Desktop: the close ✕ chip is present (mobile drops it — see below).
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _unlocked(tester);
      expect(find.text(appTitle), findsOneWidget); // 'dgvault v0.1.0'
      expect(find.textContaining('test.kdbx'), findsWidgets); // filename shown

      await tester.tap(find.byTooltip('About dgvault'));
      await tester.pump(); // start the route
      await tester.pump(const Duration(milliseconds: 700)); // fade + fly-in

      expect(find.text('dgvault'), findsOneWidget); // gradient logo wordmark
      expect(find.text(kAppCopyright), findsOneWidget);
      expect(find.text(kAppAuthors), findsOneWidget);

      // Close it (don't pumpAndSettle — the cracktro loops forever).
      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(kAppCopyright), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('About cracktro: no close chip on mobile, tap-anywhere hint',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(const MaterialApp(home: CracktroScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('tap anywhere to return'), findsOneWidget);
      expect(find.textContaining('esc'), findsNothing);
      // The ✕ chip is dropped on touch (it collides with the notch; tapping
      // anywhere dismisses instead).
      expect(find.byTooltip('Close (Esc)'), findsNothing);
      await tester.pumpWidget(const SizedBox()); // dispose looping controllers
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('About cracktro: donation chips; crypto tap copies the address',
      (tester) async {
    // Tall viewport so the chips don't sit under the bottom scroller band.
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // Capture Clipboard.setData calls (donation copies bypass the auto-clear
    // service on purpose — the address must survive an app switch).
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),);

    await tester.pumpWidget(const MaterialApp(home: CracktroScreen()));
    await tester.pump(const Duration(milliseconds: 1500)); // intro fade-in

    // All six ways to donate are shown.
    for (final label in ['paypal', 'venmo', 'cashapp', 'btc', 'eth', 'sol']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('btc'));
    expect(copied, ['1ytcdgNzF3ygR8faAcFhu3SjoexhmwdAJ']);
    await tester.tap(find.text('eth'));
    expect(copied.last, 'ytcracker.eth');
    await tester.tap(find.text('sol'));
    expect(copied.last, 'ytcdgu2BmXeqfiLR6v4Y1FMwezjL6CUNR1fy928aToQ');

    await tester.pumpWidget(const SizedBox()); // dispose looping controllers
  });

  testWidgets('tapping the cracktro dismisses it on mobile', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    try {
      await _unlocked(tester);
      // Open the About cracktro from the phone overflow menu.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('About dgvault'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(kAppCopyright), findsOneWidget); // open

      // A tap anywhere (here: empty top-left) closes it.
      await tester.tapAt(const Offset(40, 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(kAppCopyright), findsNothing); // dismissed
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone header collapses actions into an overflow menu; no '
      'keyboard hints in the status bar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844); // a phone, < wide breakpoint
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    try {
      await _unlocked(tester);

      // Header actions collapse to one overflow button (no labelled row buttons).
      expect(find.byIcon(Icons.more_vert), findsWidgets);
      expect(find.text('save'), findsNothing);
      expect(find.text('about'), findsNothing);

      // Keyboard-shortcut hints are gone on touch.
      expect(find.textContaining('copy'), findsNothing);
      expect(find.text('esc'), findsNothing);

      // Opening the overflow exposes the actions.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      expect(find.text('About dgvault'), findsOneWidget);
      expect(find.text('Lock vault'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('entry drag handles are visible on touch (no hover needed)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _unlocked(tester);
      // Select a folder so its entries become reorderable (manual sort).
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      // On touch the handle shows without any hover.
      expect(find.byIcon(Icons.drag_indicator), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('dragging the divider resizes the folder pane', (tester) async {
    await _unlocked(tester);
    final before = tester.getSize(find.byType(FolderTree)).width;

    await tester.drag(
        find.byKey(const ValueKey('resize-folder')), const Offset(50, 0),);
    await tester.pumpAndSettle();

    final after = tester.getSize(find.byType(FolderTree)).width;
    expect(after, greaterThan(before)); // pane widened with the drag
  });

  test('windowTitleFor composes version and filename', () {
    expect(windowTitleFor(null), appTitle);
    expect(windowTitleFor('v.kdbx'), '$appTitle — v.kdbx');
  });

  test('hotkeyHint omits the shortcut on mobile, shows it on desktop', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(hotkeyHint('S'), isEmpty);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(hotkeyHint('S'), ' (⌘S)');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('folder rows do not resize on hover', (tester) async {
    await _unlocked(tester);
    // 'Work' sits below 'Personal' in the tree; if hovering 'Personal' grew its
    // row, 'Work' would shift down.
    final before = tester.getTopLeft(find.text('Work')).dy;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(tester.getCenter(find.text('Personal')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsWidgets); // hover revealed actions
    expect(tester.getTopLeft(find.text('Work')).dy, before); // unchanged
  });

  testWidgets('entry rows do not resize on hover when reorderable',
      (tester) async {
    await _unlocked(tester);
    // Select a folder so its entries become drag-reorderable (manual sort).
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();

    // 'Proton Mail' sits below 'GitHub' in Personal; hovering GitHub must not
    // grow its row and push Proton Mail down.
    final before = tester.getTopLeft(find.text('Proton Mail')).dy;
    final ghInList = find.descendant(
        of: find.byType(ReorderableListView), matching: find.text('GitHub'),);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(tester.getCenter(ghInList));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_indicator), findsWidgets); // handle on hover
    expect(tester.getTopLeft(find.text('Proton Mail')).dy, before); // unchanged
  });

  testWidgets('move-to relocates the selected entry via the folder picker',
      (tester) async {
    final c = await _unlocked(tester);
    final gh = c.search('GitHub').first;
    expect(c.findGroupOf(gh)!.name, 'Personal');

    // GitHub is auto-selected in the wide detail pane → its Move action shows.
    await tester.tap(find.byTooltip('Move to folder'));
    await tester.pumpAndSettle();
    expect(find.text('// MOVE ENTRY TO'), findsOneWidget);

    // Choose 'Work' from the picker dialog (disambiguate from the sidebar).
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text('Work'),),);
    await tester.pumpAndSettle();

    expect(c.findGroupOf(gh)!.name, 'Work');
  });

  testWidgets('folder tree shows groups; Recycle Bin excluded from default view',
      (tester) async {
    await _unlocked(tester);

    // Folder sidebar lists the groups (wide/two-pane test surface).
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Recycle Bin'), findsOneWidget);

    // Default (All) view shows live entries but NOT the trashed one.
    expect(find.text('GitHub'), findsWidgets);
    expect(find.text('Jira'), findsWidgets);
    expect(find.text('Deleted Thing'), findsNothing);

    // Selecting the Recycle Bin folder reveals the trashed entry.
    await tester.tap(find.text('Recycle Bin'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted Thing'), findsWidgets);
    expect(find.text('GitHub'), findsNothing);
  });

  testWidgets('interactive controls expose hover tooltips', (tester) async {
    await _unlocked(tester);

    // header buttons (shortcut shown only on desktop, via hotkeyHint)
    expect(find.byTooltip('Generate a password${hotkeyHint('G')}'),
        findsOneWidget,);
    expect(find.byTooltip('Lock the vault${hotkeyHint('L')}'), findsOneWidget);

    // entry row (multi-line: title / user / url)
    expect(
        find.byTooltip('open GitHub\nuser: realytcracker\nhttps://github.com'),
        findsOneWidget,);

    // detail field actions (GitHub selected by default in two-pane)
    expect(find.byTooltip('Copy username'), findsOneWidget);
    expect(find.byTooltip('Reveal password'), findsOneWidget);
    expect(find.byTooltip('Copy password'), findsWidgets);

    // tag chips
    expect(find.byTooltip('tag: dev'), findsWidgets);
  });

  testWidgets('Ctrl+C is normal copy, not password-copy (no hijack)',
      (tester) async {
    // Mock the platform clipboard channel so Clipboard.setData succeeds.
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    // Swap the app-wide auto-clear service for one whose scheduler doesn't leave
    // a real Timer pending past the test.
    final saved = clipboardService;
    clipboardService = ClipboardService(scheduler: (_, __) async {});
    addTearDown(() => clipboardService = saved);
    await _unlocked(tester);

    await _ctrl(tester, LogicalKeyboardKey.keyC);
    await tester.pump();

    // ⌘/Ctrl+C must no longer copy the entry password — it stays as normal
    // text copy so selecting part of a field isn't overwritten by the password.
    expect(find.textContaining('copied password'), findsNothing);
  });
}
