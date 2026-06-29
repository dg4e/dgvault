// dgvault — terminal/hacker design system.
//
// Familiar password-manager structure, rendered as a modern terminal: deep
// blue-black surfaces, monospace type, a mint-green primary with cyan/amber/red
// accents, thin "box-drawing" borders and corner brackets. Tasteful, not a
// Matrix parody — high contrast and readable on phones and desktops alike.

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Apple platforms use ⌘ (Command); everywhere else uses Ctrl.
bool get isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// The primary modifier glyph for this platform: `⌘` on macOS/iOS, `Ctrl` else.
String get modKey => isApplePlatform ? '⌘' : 'Ctrl';

/// A platform-correct hotkey label, e.g. `⌘G` on macOS, `Ctrl+G` on Windows/Linux.
String hotkey(String key) => isApplePlatform ? '$modKey$key' : '$modKey+$key';

/// The palette. One-Dark/GitHub-dark lineage with a green primary.
class TermColors {
  static const bg = Color(0xFF0B0E14); // app background
  static const surface = Color(0xFF0F141B); // panels
  static const surfaceAlt = Color(0xFF11161F); // raised rows
  static const border = Color(0xFF1E2630);
  static const borderBright = Color(0xFF2D3947);

  static const green = Color(0xFF5CF2A0); // primary / prompt / success
  static const greenDim = Color(0xFF2E7D5B);
  static const cyan = Color(0xFF56C5D6);
  static const amber = Color(0xFFE5C07B);
  static const red = Color(0xFFE06C75);
  static const magenta = Color(0xFFC678DD);

  static const text = Color(0xFFC9D6E5); // body
  static const textBright = Color(0xFFE6EDF3);
  static const textDim = Color(0xFF6E7E91); // secondary
  static const textFaint = Color(0xFF42505F); // hints / disabled
}

/// Bundled monospace (see pubspec fonts). Falls back to system monospace fonts
/// for any glyph it might lack.
const String kMonoFamily = 'JetBrainsMono';
const List<String> kMonoFallback = <String>[
  'SF Mono',
  'Menlo',
  'Cascadia Code',
  'Consolas',
  'DejaVu Sans Mono',
  'monospace',
];

TextStyle mono({
  double size = 14,
  Color color = TermColors.text,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
  double? height,
}) =>
    TextStyle(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );

/// Responsive breakpoint: at/above this width, use the two-pane master/detail.
const double kWideBreakpoint = 760;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;

ThemeData buildTerminalTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  const scheme = ColorScheme.dark(
    primary: TermColors.green,
    onPrimary: TermColors.bg,
    secondary: TermColors.cyan,
    surface: TermColors.surface,
    onSurface: TermColors.text,
    error: TermColors.red,
  );

  TextStyle t(double s, {Color c = TermColors.text, FontWeight w = FontWeight.w400}) =>
      mono(size: s, color: c, weight: w);

  return base.copyWith(
    scaffoldBackgroundColor: TermColors.bg,
    colorScheme: scheme,
    canvasColor: TermColors.bg,
    dividerColor: TermColors.border,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: TermColors.green,
      selectionColor: Color(0x335CF2A0),
      selectionHandleColor: TermColors.green,
    ),
    textTheme: TextTheme(
      displaySmall: t(26, c: TermColors.textBright, w: FontWeight.w700),
      headlineSmall: t(20, c: TermColors.textBright, w: FontWeight.w600),
      titleMedium: t(15, c: TermColors.textBright, w: FontWeight.w600),
      bodyLarge: t(15),
      bodyMedium: t(14),
      bodySmall: t(12, c: TermColors.textDim),
      labelLarge: t(13, c: TermColors.textBright, w: FontWeight.w600),
      labelSmall: t(11, c: TermColors.textDim),
    ),
    iconTheme: const IconThemeData(color: TermColors.textDim, size: 18),
  );
}
