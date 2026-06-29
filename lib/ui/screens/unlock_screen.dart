// dgvault — unlock screen: master-password prompt for the loaded .kdbx file.

import 'package:flutter/material.dart';

import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/banner_logo.dart';
import '../widgets/terminal_widgets.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pw = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _pw.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final pw = _pw.text;
    if (pw.isEmpty) return;
    widget.controller.unlock(pw);
    _pw.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.status == VaultStatus.unlocking;
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
                    title: 'unlock',
                    accent:
                        c.error != null ? TermColors.red : TermColors.border,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('file: ',
                                style:
                                    mono(size: 12, color: TermColors.textDim),),
                            Flexible(
                              child: Text(
                                c.fileName ?? '(in memory)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(size: 12, color: TermColors.cyan),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const SectionLabel('master password'),
                        PromptField(
                          controller: _pw,
                          focusNode: _focus,
                          autofocus: true,
                          obscure: true,
                          hint: 'enter master password…',
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            TermButton(
                              label: busy ? 'DECRYPTING' : 'UNLOCK',
                              busy: busy,
                              tooltip: c.lockedOut
                                  ? 'Locked out — close and reopen'
                                  : 'Decrypt and open the vault (Enter)',
                              onPressed: (busy || c.lockedOut) ? null : _submit,
                            ),
                            const Spacer(),
                            TermButton(
                              label: 'CLOSE',
                              color: TermColors.textDim,
                              tooltip: 'Close this file (resets the lockout)',
                              onPressed: busy ? null : c.close,
                            ),
                          ],
                        ),
                        if (c.error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            '!! ${c.error}',
                            style: mono(size: 12, color: TermColors.red),
                          ),
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
