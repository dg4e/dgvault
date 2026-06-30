// dgvault — landing screen: open an existing .kdbx or create a new one.

import 'package:flutter/material.dart';

import '../state/file_service.dart';
import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/banner_logo.dart';
import '../widgets/terminal_widgets.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key, required this.controller});
  final VaultController controller;

  Future<void> _open(BuildContext context) async {
    final path = await VaultFiles.pickOpen();
    if (path != null) await controller.openFile(path);
  }

  Future<void> _new(BuildContext context) async {
    final path = await VaultFiles.pickNew();
    if (path == null) return;
    if (!context.mounted) return;
    final pw = await _promptNewPassword(context);
    if (pw == null || pw.isEmpty) return;
    await controller.createNew(path, pw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BannerLogo(),
                  const SizedBox(height: 28),
                  TerminalPanel(
                    title: 'no vault loaded',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'open an existing KeePass database (.kdbx) or create a '
                          'new one.',
                          style: mono(size: 12, color: TermColors.textDim),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            TermButton(
                              label: 'OPEN .KDBX',
                              tooltip: 'Open an existing vault${hotkeyHint('O')}',
                              onPressed: () => _open(context),
                            ),
                            TermButton(
                              label: 'NEW VAULT',
                              color: TermColors.cyan,
                              tooltip: 'Create a new vault${hotkeyHint('N')}',
                              onPressed: () => _new(context),
                            ),
                          ],
                        ),
                        if (controller.error != null) ...[
                          const SizedBox(height: 14),
                          Text('!! ${controller.error}',
                              style: mono(size: 12, color: TermColors.red),),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal: set the master password for a brand-new vault (with confirmation).
Future<String?> _promptNewPassword(BuildContext context) {
  final pw = TextEditingController();
  final confirm = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      String? err;
      return StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TerminalPanel(
              title: 'set master password',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('master password'),
                  PromptField(
                      controller: pw,
                      obscure: true,
                      autofocus: true,
                      hint: 'password…',),
                  const SizedBox(height: 12),
                  const SectionLabel('confirm'),
                  PromptField(
                      controller: confirm, obscure: true, hint: 'repeat…',),
                  if (err != null) ...[
                    const SizedBox(height: 12),
                    Text('!! $err',
                        style: mono(size: 12, color: TermColors.red),),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TermButton(
                        label: 'CANCEL',
                        color: TermColors.textDim,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      TermButton(
                        label: 'CREATE',
                        onPressed: () {
                          if (pw.text.isEmpty) {
                            setState(() => err = 'password cannot be empty');
                          } else if (pw.text != confirm.text) {
                            setState(() => err = 'passwords do not match');
                          } else {
                            Navigator.pop(context, pw.text);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
