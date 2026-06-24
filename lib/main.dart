// dgvault — application entry point (host shell).
//
// Minimal runnable shell so the platform host projects (android/ios/macos/linux/
// windows) have an entrypoint and the platform adapters can be exercised on a
// device. The real UI (Phase 7) lives under lib/ui; this is intentionally a
// placeholder home screen, not the finished app.

import 'package:flutter/material.dart';

void main() => runApp(const DgvaultApp());

class DgvaultApp extends StatelessWidget {
  const DgvaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dgvault',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('dgvault')),
      body: const Center(
        child: Text('dgvault — secure vault\n(UI under construction)',
            textAlign: TextAlign.center,),
      ),
    );
  }
}
