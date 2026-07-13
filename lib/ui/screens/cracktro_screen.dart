// dgvault — "About" screen done as an Amiga-style cracktro: copper bars, a
// starfield, a fly-in gradient logo, and a sine-wave scrolltext. Pure Flutter
// painting + animation; no assets beyond the bundled mono font.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../theme/terminal_theme.dart';

/// Push the cracktro as a full-screen route (fades in over the current screen).
Future<void> showCracktro(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, anim, __) =>
          FadeTransition(opacity: anim, child: const CracktroScreen()),
    ),
  );
}

String get _scrollText =>
    'DGVAULT V$appVersion ... $kAppCopyright ... $kAppAuthors ... '
    'KEEP YOUR SECRETS DANGEROUS ... ONE VAULT TO RULE THE KEEP ... '
    'GREETZ TO THE WHOLE SCENE AND EVERYONE STILL CRACKING THE GOOD CODE ... '
    'STAY FREE ... STAY ENCRYPTED ...     ';

class CracktroScreen extends StatefulWidget {
  const CracktroScreen({super.key});

  @override
  State<CracktroScreen> createState() => _CracktroScreenState();
}

class _CracktroScreenState extends State<CracktroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final List<_Star> _stars = _makeStars();

  List<_Star> _makeStars() {
    final rnd = math.Random(0xC0FFEE);
    return List.generate(140, (_) {
      return _Star(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        speed: 0.05 + rnd.nextDouble() * 0.6,
        size: 0.5 + rnd.nextDouble() * 1.8,
        phase: rnd.nextDouble(),
      );
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final logoIn = CurvedAnimation(parent: _intro, curve: Curves.elasticOut);
    final fadeIn = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.45, 1, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          autofocus: true,
          child: GestureDetector(
            // On touch devices, tapping anywhere dismisses the cracktro.
            onTap: isMobilePlatform ? _close : null,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                // Animated copper-bar + starfield background.
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (_, __) => CustomPaint(
                      painter: _BackdropPainter(t: _loop.value, stars: _stars),
                    ),
                  ),
                ),

                // Centre: fly-in gradient logo + credits.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -1.6),
                          end: Offset.zero,
                        ).animate(logoIn),
                        child: ScaleTransition(
                          scale:
                              Tween<double>(begin: 0.6, end: 1).animate(logoIn),
                          child: _GradientLogo(loop: _loop),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FadeTransition(
                        opacity: fadeIn,
                        child: Column(
                          children: [
                            _credit(
                              'v$appVersion',
                              TermColors.green,
                              16,
                              weight: FontWeight.w700,
                            ),
                            const SizedBox(height: 10),
                            _credit(kAppCopyright, TermColors.cyan, 13),
                            const SizedBox(height: 4),
                            _credit(kAppAuthors, TermColors.magenta, 13),
                            const SizedBox(height: 22),
                            const _DonationSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom: sine-wave scroller.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 54,
                  height: 110,
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (_, __) => CustomPaint(
                      painter: _ScrollerPainter(t: _loop.value),
                      size: Size.infinite,
                    ),
                  ),
                ),

                // Close affordance (desktop only — on touch, tap anywhere to
                // dismiss, and a top-corner chip collides with the notch).
                if (!isMobilePlatform)
                  Positioned(
                    top: 14,
                    right: 16,
                    child: _CloseChip(onTap: _close),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Center(
                    child: Text(
                      // No physical keyboard on phones/tablets — drop the Esc hint.
                      isMobilePlatform
                          ? 'tap anywhere to return'
                          : 'press [esc] or click ✕ to return',
                      style: mono(size: 11, color: TermColors.textFaint),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _credit(
    String text,
    Color color,
    double size, {
    FontWeight weight = FontWeight.w500,
  }) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: mono(size: size, color: color, weight: weight, letterSpacing: 1),
    );
  }
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.phase,
  });
  final double x; // 0..1
  final double y; // 0..1
  final double speed;
  final double size;
  final double phase;
}

/// Copper bars + drifting starfield.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.t, required this.stars});
  final double t;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Deep vertical gradient base.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF03100B), Color(0xFF000000), Color(0xFF06121A)],
        ).createShader(rect),
    );

    // Starfield — drifts leftward, twinkles.
    for (final s in stars) {
      final sx = ((s.x - t * s.speed) % 1.0) * size.width;
      final sy = s.y * size.height;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin((t + s.phase) * 6.283 * 2));
      canvas.drawCircle(
        Offset(sx, sy),
        s.size,
        Paint()..color = Colors.white.withValues(alpha: 0.7 * tw),
      );
    }

    // Copper bars — smooth coloured horizontal bands sweeping up and down.
    const bars = 7;
    const barH = 54.0;
    for (var b = 0; b < bars; b++) {
      final phase = t * 6.283 + b * (6.283 / bars);
      final cy = size.height * 0.5 + math.sin(phase) * size.height * 0.36;
      final hue = ((b / bars) + t) % 1.0 * 360.0;
      final base = HSVColor.fromAHSV(1, hue, 0.85, 1).toColor();
      final band = Rect.fromLTWH(0, cy - barH / 2, size.width, barH);
      canvas.drawRect(
        band,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              base.withValues(alpha: 0.0),
              base.withValues(alpha: 0.5),
              Colors.white.withValues(alpha: 0.85),
              base.withValues(alpha: 0.5),
              base.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.32, 0.5, 0.68, 1.0],
          ).createShader(band),
      );
    }

    // Subtle vignette so the centre text stays readable over the bars.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t;
}

/// Big gradient wordmark with an animated sheen.
class _GradientLogo extends StatelessWidget {
  const _GradientLogo({required this.loop});
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (_, __) {
        final shift = loop.value * 2 - 1; // -1..1 sweep
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1 + shift, -1),
            end: Alignment(1 + shift, 1),
            colors: const [
              Color(0xFF5CF2A0),
              Color(0xFF56C5D6),
              Color(0xFFC678DD),
              Color(0xFF5CF2A0),
            ],
            stops: const [0.0, 0.4, 0.7, 1.0],
          ).createShader(rect),
          child: Text(
            kAppName,
            style: mono(
              size: 84,
              color: Colors.white,
              weight: FontWeight.w900,
              letterSpacing: 2,
            ).copyWith(
              shadows: const [
                Shadow(color: Color(0x885CF2A0), blurRadius: 28),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Classic demoscene sine-wave scroller: each glyph rides a travelling sine,
/// cycling rainbow colours, looping seamlessly.
class _ScrollerPainter extends CustomPainter {
  _ScrollerPainter({required this.t});
  final double t;

  static const double _fontSize = 34;
  static const double _adv = _fontSize * 0.6; // JetBrains Mono advance ≈ 0.6em

  @override
  void paint(Canvas canvas, Size size) {
    final chars = _scrollText.split('');
    final single = chars.length * _adv;
    final shift = (t * single) % single; // continuous leftward scroll
    final baseY = size.height / 2;
    final tiles = (size.width / single).ceil() + 2;

    for (var tile = 0; tile < tiles; tile++) {
      final tileX = -shift + tile * single;
      for (var i = 0; i < chars.length; i++) {
        final x = tileX + i * _adv;
        if (x < -_adv || x > size.width) continue;
        final wave = math.sin(x * 0.012 + t * 6.283 * 3);
        final y = baseY + wave * 26;
        final hue = (((tile * chars.length + i) * 0.012 + t) % 1.0) * 360.0;
        final color = HSVColor.fromAHSV(1, hue, 0.7, 1).toColor();
        final tp = TextPainter(
          text: TextSpan(
            text: chars[i],
            style: mono(
              size: _fontSize,
              color: color,
              weight: FontWeight.w800,
            ).copyWith(
              shadows: [
                Shadow(color: color.withValues(alpha: 0.6), blurRadius: 12),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_ScrollerPainter old) => old.t != t;
}

/// One way to send a donation: a brand logo + label chip. Tapping either opens
/// the profile page (fiat) or copies the address to the clipboard (crypto).
class _DonationTarget {
  const _DonationTarget(
    this.asset,
    this.label,
    this.detail, {
    this.url,
    this.copyValue,
  });
  final String asset; // assets/brands/<name>.png
  final String label;
  final String detail; // handle/address, shown in the tooltip
  final String? url; // open in browser…
  final String? copyValue; // …or copy to clipboard
}

const List<_DonationTarget> _kDonationTargets = [
  _DonationTarget(
    'assets/brands/paypal.png',
    'paypal',
    'sales@digitalgangster.com',
    url: 'https://www.paypal.com/donate/?business=sales%40digitalgangster.com',
  ),
  _DonationTarget(
    'assets/brands/venmo.png',
    'venmo',
    '@dge-llc',
    url: 'https://venmo.com/u/dge-llc',
  ),
  _DonationTarget(
    'assets/brands/cashapp.png',
    'cashapp',
    r'$dgeternal',
    url: r'https://cash.app/$dgeternal',
  ),
  _DonationTarget(
    'assets/brands/bitcoin.png',
    'btc',
    '1ytcdgNzF3ygR8faAcFhu3SjoexhmwdAJ',
    copyValue: '1ytcdgNzF3ygR8faAcFhu3SjoexhmwdAJ',
  ),
  _DonationTarget(
    'assets/brands/ethereum.png',
    'eth',
    'ytcracker.eth',
    copyValue: 'ytcracker.eth',
  ),
  _DonationTarget(
    'assets/brands/solana.png',
    'sol',
    'ytcdgu2BmXeqfiLR6v4Y1FMwezjL6CUNR1fy928aToQ',
    copyValue: 'ytcdgu2BmXeqfiLR6v4Y1FMwezjL6CUNR1fy928aToQ',
  ),
];

/// "support the scene" — donation chips under the credits.
class _DonationSection extends StatelessWidget {
  const _DonationSection();

  Future<void> _activate(BuildContext context, _DonationTarget t) async {
    if (t.url != null) {
      await launchUrl(Uri.parse(t.url!), mode: LaunchMode.externalApplication);
      return;
    }
    // Plain copy, NOT the auto-clearing ClipboardService — a donation address
    // must survive switching to a wallet app to paste it.
    await Clipboard.setData(ClipboardData(text: t.copyValue!));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: TermColors.surfaceAlt,
          duration: const Duration(seconds: 2),
          content: Text(
            '✓ copied ${t.label} address to clipboard',
            style: mono(size: 12, color: TermColors.green),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        children: [
          Text(
            '// support the scene',
            style: mono(size: 12, color: TermColors.textDim, letterSpacing: 1),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _kDonationTargets)
                Tooltip(
                  message: t.url != null ? t.detail : '${t.detail} (tap to copy)',
                  child: InkWell(
                    onTap: () => _activate(context, t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        border: Border.all(color: TermColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(t.asset, width: 16, height: 16),
                          const SizedBox(width: 7),
                          Text(
                            t.label,
                            style: mono(size: 12, color: TermColors.text),
                          ),
                          if (t.copyValue != null) ...[
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.content_copy_outlined,
                              size: 11,
                              color: TermColors.textFaint,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloseChip extends StatelessWidget {
  const _CloseChip({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close (Esc)',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            border: Border.all(color: TermColors.border),
          ),
          child:
              const Icon(Icons.close, size: 18, color: TermColors.textBright),
        ),
      ),
    );
  }
}
