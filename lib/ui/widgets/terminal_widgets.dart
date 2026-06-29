// dgvault — reusable terminal-UI chrome.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/terminal_theme.dart';

/// A blinking block cursor.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, this.color = TermColors.green, this.width = 9, this.height = 16});
  final Color color;
  final double width;
  final double height;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Opacity(
        opacity: _c.value < 0.5 ? 1 : 0.05,
        child: Container(
          width: widget.width,
          height: widget.height,
          color: widget.color,
        ),
      ),
    );
  }
}

/// A bordered panel with corner brackets and an optional title in the top edge.
class TerminalPanel extends StatelessWidget {
  const TerminalPanel({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(16),
    this.accent = TermColors.border,
  });

  final Widget child;
  final String? title;
  final EdgeInsets padding;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The title straddles the top border (top: -8), so it must not be clipped.
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: TermColors.surface,
            border: Border.all(color: accent),
          ),
          padding: padding,
          width: double.infinity,
          child: child,
        ),
        if (title != null)
          Positioned(
            left: 12,
            top: -8,
            child: Container(
              color: TermColors.bg,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('┤ ${title!} ├',
                  style: mono(size: 11, color: TermColors.green, weight: FontWeight.w600),),
            ),
          ),
      ],
    );
  }
}

/// Dim `// section` header.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('// ${label.toUpperCase()}',
            style: mono(size: 11, color: TermColors.textDim, letterSpacing: 1.5),),
      );
}

/// `[ label ]` terminal button with focus/hover glow.
class TermButton extends StatefulWidget {
  const TermButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = TermColors.green,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool busy;

  @override
  State<TermButton> createState() => _TermButtonState();
}

class _TermButtonState extends State<TermButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final c = enabled ? widget.color : TermColors.textFaint;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: c),
            color: _hover && enabled ? c.withValues(alpha: 0.12) : Colors.transparent,
            boxShadow: _hover && enabled
                ? [BoxShadow(color: c.withValues(alpha: 0.25), blurRadius: 12)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.busy) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: c),
                ),
                const SizedBox(width: 10),
              ],
              Text('[ ${widget.label} ]',
                  style: mono(size: 13, color: c, weight: FontWeight.w600),),
            ],
          ),
        ),
      ),
    );
  }
}

/// A terminal prompt input: a coloured sigil prefix + a borderless field.
class PromptField extends StatelessWidget {
  const PromptField({
    super.key,
    required this.controller,
    this.sigil = '>',
    this.hint = '',
    this.obscure = false,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.sigilColor = TermColors.green,
  });

  final TextEditingController controller;
  final String sigil;
  final String hint;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final Color sigilColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TermColors.surfaceAlt,
        border: Border(bottom: BorderSide(color: TermColors.borderBright)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text('$sigil ', style: mono(color: sigilColor, weight: FontWeight.w700)),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              obscureText: obscure,
              obscuringCharacter: '•',
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              cursorColor: TermColors.green,
              cursorWidth: 9,
              style: mono(size: 14, color: TermColors.textBright),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: mono(size: 14, color: TermColors.textFaint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// vim/tmux-style status bar split into left and right segments.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.left, required this.right, this.mode = 'READY', this.modeColor = TermColors.green});
  final List<String> left;
  final List<String> right;
  final String mode;
  final Color modeColor;

  @override
  Widget build(BuildContext context) {
    Widget seg(String s, Color fg, Color bg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          color: bg,
          child: Text(s, style: mono(size: 11, color: fg, weight: FontWeight.w600)),
        );
    Widget item(String s) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(s, style: mono(size: 11, color: TermColors.textDim)),
        );
    return Container(
      color: TermColors.surface,
      child: Row(
        children: [
          seg(mode, TermColors.bg, modeColor),
          for (final s in left) item(s),
          const Spacer(),
          // Right hints can be many on desktop; scroll horizontally rather than
          // overflow on a narrow phone (keeps the trailing end visible).
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: [for (final s in right) item(s)]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small `#tag` chip.
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.color = TermColors.magenta});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.6))),
        child: Text('#$label', style: mono(size: 11, color: color)),
      );
}

/// Copy [value] to the clipboard and flash a status snackbar.
Future<void> copyWithFlash(BuildContext context, String value, String label) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: TermColors.surfaceAlt,
      duration: const Duration(seconds: 2),
      content: Text('✓ copied $label to clipboard — auto-clears',
          style: mono(size: 12, color: TermColors.green),),
    ),);
}
