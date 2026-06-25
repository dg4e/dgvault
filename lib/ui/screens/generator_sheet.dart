// dgvault — password generator panel (real PasswordGenerator engine).

import 'package:flutter/material.dart';

import 'package:dgvault/core/generator/password_generator.dart';

import '../theme/terminal_theme.dart';
import '../widgets/terminal_widgets.dart';

void showGenerator(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: TermColors.bg,
    isScrollControlled: true,
    builder: (_) => const _GeneratorSheet(),
  );
}

class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet();
  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  final _gen = PasswordGenerator();
  double _length = 20;
  bool _upper = true, _lower = true, _digits = true, _symbols = true;
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

  void _regen() {
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text('// PASSWORD GENERATOR',
                  style: mono(size: 12, color: TermColors.textDim, letterSpacing: 1.5),),
              const Spacer(),
              _IconBtn(icon: Icons.refresh, onTap: _regen),
              _IconBtn(
                  icon: Icons.content_copy_outlined,
                  onTap: () => copyWithFlash(context, _output, 'password'),),
            ],),
            const SizedBox(height: 12),
            TerminalPanel(
              accent: _strengthColor,
              child: SelectableText(_output,
                  style: mono(size: 16, color: TermColors.textBright, height: 1.4),),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text('entropy: ${_bits.toStringAsFixed(1)} bits',
                  style: mono(size: 12, color: _strengthColor),),
              const SizedBox(width: 10),
              Text(_bits >= 100 ? 'STRONG' : _bits >= 60 ? 'OK' : 'WEAK',
                  style: mono(size: 12, color: _strengthColor, weight: FontWeight.w700),),
            ],),
            const SizedBox(height: 16),
            Row(children: [
              Text('length ${_length.round()}',
                  style: mono(size: 13, color: TermColors.text),),
              Expanded(
                child: Slider(
                  value: _length, min: 6, max: 64, divisions: 58,
                  activeColor: TermColors.green, inactiveColor: TermColors.border,
                  onChanged: (v) { setState(() => _length = v); _regen(); },
                ),
              ),
            ],),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _Toggle(label: 'A-Z', on: _upper, onTap: () { setState(() => _upper = !_upper); _regen(); }),
              _Toggle(label: 'a-z', on: _lower, onTap: () { setState(() => _lower = !_lower); _regen(); }),
              _Toggle(label: '0-9', on: _digits, onTap: () { setState(() => _digits = !_digits); _regen(); }),
              _Toggle(label: '!@#', on: _symbols, onTap: () { setState(() => _symbols = !_symbols); _regen(); }),
            ],),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = on ? TermColors.green : TermColors.textFaint;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: c),
          color: on ? c.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text('${on ? "[x]" : "[ ]"} $label', style: mono(size: 13, color: c)),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: TermColors.textDim),),
      );
}
