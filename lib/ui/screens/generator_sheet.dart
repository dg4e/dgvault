// dgvault — password generator panel (real PasswordGenerator engine).

import 'package:flutter/material.dart';

import 'package:dgvault/core/generator/diceware_generator.dart';
import 'package:dgvault/core/generator/password_generator.dart';

import '../theme/terminal_theme.dart';
import '../widgets/terminal_widgets.dart';

bool _generatorOpen = false;

/// Open the generator. When [onUse] is given, a "USE" button feeds the generated
/// password back to the caller (e.g. the entry editor) and closes the sheet.
void showGenerator(BuildContext context, {ValueChanged<String>? onUse}) {
  // Repeated ⌘G / taps must not stack sheets.
  if (_generatorOpen) return;
  _generatorOpen = true;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: TermColors.bg,
    isScrollControlled: true,
    builder: (_) => _GeneratorSheet(onUse: onUse),
  ).whenComplete(() => _generatorOpen = false);
}

class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet({this.onUse});
  final ValueChanged<String>? onUse;
  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

enum _GenMode { password, passphrase }

class _GeneratorSheetState extends State<_GeneratorSheet> {
  final _gen = PasswordGenerator();
  final _diceware = DicewareGenerator.standard();

  _GenMode _mode = _GenMode.password;

  // Charset (password) options.
  double _length = 20;
  bool _upper = true, _lower = true, _digits = true, _symbols = true;

  // Passphrase (diceware) options.
  double _words = 6;
  String _separator = '-';
  DicewareCapitalization _caps = DicewareCapitalization.none;
  bool _wordNumber = false;

  String _output = '';
  double _bits = 0;

  @override
  void initState() {
    super.initState();
    _regen();
  }

  PasswordOptions get _opts => PasswordOptions(
        length: _length.round(),
        useUppercase: _upper,
        useLowercase: _lower,
        useDigits: _digits,
        useSymbols: _symbols,
        requireEachSelectedClass: false,
      );

  DicewareOptions get _dopts => DicewareOptions(
        wordCount: _words.round(),
        separator: _separator,
        capitalization: _caps,
        includeNumber: _wordNumber,
      );

  void _regen() {
    if (_mode == _GenMode.passphrase) {
      setState(() {
        _output = _diceware.generate(_dopts);
        _bits = _diceware.estimateEntropyBits(_dopts);
      });
      return;
    }
    try {
      setState(() {
        _output = _gen.generate(_opts);
        _bits = _gen.estimateEntropyBits(_opts);
      });
    } on PasswordGenerationException {
      setState(() {
        _output = '— enable a character class —';
        _bits = 0;
      });
    }
  }

  Color get _strengthColor => _bits >= 100
      ? TermColors.green
      : _bits >= 60
          ? TermColors.amber
          : TermColors.red;

  List<Widget> _passwordControls() => [
        Row(
          children: [
            Text(
              'length ${_length.round()}',
              style: mono(size: 13, color: TermColors.text),
            ),
            Expanded(
              child: Slider(
                value: _length,
                min: 6,
                max: 64,
                divisions: 58,
                activeColor: TermColors.green,
                inactiveColor: TermColors.border,
                onChanged: (v) {
                  setState(() => _length = v);
                  _regen();
                },
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Toggle(
              label: 'A-Z',
              tooltip: 'Include uppercase letters',
              on: _upper,
              onTap: () {
                setState(() => _upper = !_upper);
                _regen();
              },
            ),
            _Toggle(
              label: 'a-z',
              tooltip: 'Include lowercase letters',
              on: _lower,
              onTap: () {
                setState(() => _lower = !_lower);
                _regen();
              },
            ),
            _Toggle(
              label: '0-9',
              tooltip: 'Include digits',
              on: _digits,
              onTap: () {
                setState(() => _digits = !_digits);
                _regen();
              },
            ),
            _Toggle(
              label: '!@#',
              tooltip: 'Include symbols',
              on: _symbols,
              onTap: () {
                setState(() => _symbols = !_symbols);
                _regen();
              },
            ),
          ],
        ),
      ];

  List<Widget> _passphraseControls() => [
        Row(
          children: [
            Text(
              'words ${_words.round()}',
              style: mono(size: 13, color: TermColors.text),
            ),
            Expanded(
              child: Slider(
                value: _words,
                min: 3,
                max: 12,
                divisions: 9,
                activeColor: TermColors.green,
                inactiveColor: TermColors.border,
                onChanged: (v) {
                  setState(() => _words = v);
                  _regen();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('separator', style: mono(size: 12, color: TermColors.textDim)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in const [
              ('-', 'dash'),
              ('.', 'dot'),
              (' ', 'space'),
              ('_', 'underscore'),
              ('', 'none'),
            ])
              _Toggle(
                label: s.$2,
                on: _separator == s.$1,
                onTap: () {
                  setState(() => _separator = s.$1);
                  _regen();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Toggle(
              label: 'Capitalize',
              tooltip: 'Capitalize the first letter of each word',
              on: _caps == DicewareCapitalization.firstLetterEachWord,
              onTap: () {
                setState(
                  () => _caps =
                      _caps == DicewareCapitalization.firstLetterEachWord
                          ? DicewareCapitalization.none
                          : DicewareCapitalization.firstLetterEachWord,
                );
                _regen();
              },
            ),
            _Toggle(
              label: 'Add number',
              tooltip: 'Append a random digit to one word',
              on: _wordNumber,
              onTap: () {
                setState(() => _wordNumber = !_wordNumber);
                _regen();
              },
            ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '// PASSWORD GENERATOR',
                  style: mono(
                    size: 12,
                    color: TermColors.textDim,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                _IconBtn(
                  icon: Icons.refresh,
                  tooltip: 'Regenerate',
                  onTap: _regen,
                ),
                _IconBtn(
                  icon: Icons.content_copy_outlined,
                  tooltip: 'Copy password',
                  onTap: () => copyWithFlash(context, _output, 'password'),
                ),
                _IconBtn(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Mode switch: charset password vs diceware passphrase.
            Row(
              children: [
                _ModeTab(
                  label: 'password',
                  on: _mode == _GenMode.password,
                  onTap: () {
                    setState(() => _mode = _GenMode.password);
                    _regen();
                  },
                ),
                const SizedBox(width: 8),
                _ModeTab(
                  label: 'passphrase',
                  on: _mode == _GenMode.passphrase,
                  onTap: () {
                    setState(() => _mode = _GenMode.passphrase);
                    _regen();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            TerminalPanel(
              accent: _strengthColor,
              child: SelectableText(
                _output,
                style:
                    mono(size: 16, color: TermColors.textBright, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'entropy: ${_bits.toStringAsFixed(1)} bits',
                  style: mono(size: 12, color: _strengthColor),
                ),
                const SizedBox(width: 10),
                Text(
                  _bits >= 100
                      ? 'STRONG'
                      : _bits >= 60
                          ? 'OK'
                          : 'WEAK',
                  style: mono(
                    size: 12,
                    color: _strengthColor,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_mode == _GenMode.password)
              ..._passwordControls()
            else
              ..._passphraseControls(),
            if (widget.onUse != null) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TermButton(
                  label: 'USE',
                  tooltip: 'Use this password',
                  onPressed: () {
                    widget.onUse!(_output);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.on,
    required this.onTap,
    this.tooltip,
  });
  final String label;
  final bool on;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final c = on ? TermColors.green : TermColors.textFaint;
    return Tooltip(
      message: tooltip ?? label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: c),
            color: on ? c.withValues(alpha: 0.12) : Colors.transparent,
          ),
          child: Text(
            '${on ? "[x]" : "[ ]"} $label',
            style: mono(size: 13, color: c),
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = on ? TermColors.green : TermColors.textFaint;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: c),
          color: on ? c.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(label, style: mono(size: 13, color: c)),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: TermColors.textDim),
          ),
        ),
      );
}
