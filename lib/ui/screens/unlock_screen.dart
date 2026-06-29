// dgvault — unlock screen: terminal boot + passphrase prompt.

import 'package:flutter/material.dart';

import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/app_menu.dart';
import '../widgets/terminal_widgets.dart';

const _banner = r'''
    _                    _ _
 __| |__ ___ ____ _ _  _| | |_
/ _` / _` \ V / _` | || | |  _|
\__,_\__, |\_/\__,_|\_,_|_|\__|
     |___/
     secure vault · kdbx4 · zero-knowledge''';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pin = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pin.text.trim();
    if (pin.isEmpty) return;
    widget.controller.attempt(pin);
    _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.status == VaultStatus.unlocking;
    return appMenuBar(
      child: Scaffold(
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _banner,
                        style: mono(
                            size: 13, color: TermColors.green, height: 1.25,),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TerminalPanel(
                      title: 'authenticate',
                      accent:
                          c.error != null ? TermColors.red : TermColors.border,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _BootLog(),
                          const SizedBox(height: 14),
                          const SectionLabel('master pin'),
                          PromptField(
                            controller: _pin,
                            focusNode: _focus,
                            autofocus: true,
                            obscure: true,
                            hint: 'enter pin…',
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              TermButton(
                                label: busy ? 'DECRYPTING' : 'UNLOCK',
                                busy: busy,
                                onPressed: busy ? null : _submit,
                              ),
                              const Spacer(),
                              if (c.lockedOut)
                                TermButton(
                                  label: 'RESET',
                                  color: TermColors.amber,
                                  onPressed: c.resetLockout,
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
                    const SizedBox(height: 14),
                    Text(
                      'hint: demo pin is ${VaultController.demoPin}',
                      style: mono(size: 11, color: TermColors.textFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootLog extends StatelessWidget {
  const _BootLog();
  @override
  Widget build(BuildContext context) {
    const lines = [
      ('mount', 'encrypted volume  [ok]'),
      ('kdf', 'argon2id  [ready]'),
      ('cipher', 'aes-256 + hmac-sha256  [ready]'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (k, v) in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                      text: '  ➜ ',
                      style: mono(size: 12, color: TermColors.greenDim),),
                  TextSpan(
                      text: '$k: ',
                      style: mono(size: 12, color: TermColors.textDim),),
                  TextSpan(
                      text: v, style: mono(size: 12, color: TermColors.text),),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
