// dgvault — root app: owns the VaultController and routes lock ⇄ unlock.

import 'package:flutter/material.dart';

import 'screens/unlock_screen.dart';
import 'screens/vault_screen.dart';
import 'state/vault_controller.dart';
import 'theme/terminal_theme.dart';
import 'widgets/terminal_widgets.dart';

class DgvaultApp extends StatefulWidget {
  const DgvaultApp({super.key, this.controller});

  /// Inject a pre-bootstrapped controller (tests); otherwise one is created.
  final VaultController? controller;

  @override
  State<DgvaultApp> createState() => _DgvaultAppState();
}

class _DgvaultAppState extends State<DgvaultApp> {
  late final VaultController _controller = widget.controller ?? VaultController();

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _controller.bootstrap();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dgvault',
      debugShowCheckedModeBanner: false,
      theme: buildTerminalTheme(),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          switch (_controller.status) {
            case VaultStatus.booting:
              return const _BootScreen();
            case VaultStatus.unlocked:
              return VaultScreen(controller: _controller);
            case VaultStatus.locked:
            case VaultStatus.unlocking:
              return UnlockScreen(controller: _controller);
          }
        },
      ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('dgvault: booting',
                style: mono(color: TermColors.green, weight: FontWeight.w600),),
            const SizedBox(width: 6),
            const BlinkingCursor(),
          ],
        ),
      ),
    );
  }
}
