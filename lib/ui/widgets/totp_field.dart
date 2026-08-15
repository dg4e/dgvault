// dgvault — live TOTP code display for an entry's stored 2FA secret.
//
// The entry stores a "TOTP" string that is either a full `otpauth://totp/...`
// URI (what a QR code encodes) or a bare Base32 secret. This widget parses it,
// computes the current rotating code via the real [Totp] engine (RFC 6238), and
// refreshes once a second with a countdown ring until the code rolls over.
// Tapping copies the current code (auto-clearing clipboard, like passwords).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/otp/impl/pointycastle_hmac.dart';

import '../theme/terminal_theme.dart';
import 'terminal_widgets.dart';

/// Parse a stored TOTP string into an [OtpConfig], or null if it isn't a valid
/// otpauth URI / Base32 secret. Pure — safe to call in a build.
OtpConfig? parseStoredTotp(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  try {
    if (s.toLowerCase().startsWith('otpauth://')) return OtpConfig.fromUri(s);
    // Bare secret: Base32, default TOTP params. Reject if it decodes to nothing.
    final secret = base32Decode(s);
    if (secret.isEmpty) return null;
    return OtpConfig(secret: secret);
  } catch (_) {
    return null;
  }
}

class TotpField extends StatefulWidget {
  const TotpField({super.key, required this.rawSecret});

  /// The raw stored value (otpauth URI or Base32 secret).
  final String rawSecret;

  @override
  State<TotpField> createState() => _TotpFieldState();
}

class _TotpFieldState extends State<TotpField> {
  static const _totp = Totp(PointyCastleOtpHmac());

  OtpConfig? _config;
  Timer? _ticker;
  String _code = '';
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _config = parseStoredTotp(widget.rawSecret);
    _refresh();
    if (_config != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    }
  }

  @override
  void didUpdateWidget(TotpField old) {
    super.didUpdateWidget(old);
    if (old.rawSecret != widget.rawSecret) {
      _ticker?.cancel();
      _config = parseStoredTotp(widget.rawSecret);
      _refresh();
      if (_config != null) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
      }
    }
  }

  void _refresh() {
    final c = _config;
    if (c == null) return;
    final now = DateTime.now();
    final next = _totp.generate(c, now);
    final rem = _totp.remainingSeconds(c, now);
    if (mounted) {
      setState(() {
        _code = next;
        _remaining = rem;
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Group the code as "123 456" (or "12345" left as-is for Steam) for reading.
  String get _pretty {
    if (_code.length == 6) return '${_code.substring(0, 3)} ${_code.substring(3)}';
    if (_code.length == 8) return '${_code.substring(0, 4)} ${_code.substring(4)}';
    return _code;
  }

  @override
  Widget build(BuildContext context) {
    final period = _config?.period ?? 30;
    if (_config == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('one-time code'),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: TermColors.surfaceAlt,
                border: Border(
                  left: BorderSide(color: TermColors.amber, width: 2),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                'invalid TOTP secret (expected otpauth:// URI or Base32)',
                style: mono(size: 12, color: TermColors.amber),
              ),
            ),
          ],
        ),
      );
    }

    // The countdown turns amber in the last 5 seconds.
    final warn = _remaining <= 5;
    final ringColor = warn ? TermColors.amber : TermColors.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('one-time code (2fa)'),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => copyWithFlash(context, _code, 'code'),
                  child: Container(
                    decoration: BoxDecoration(
                      color: TermColors.surfaceAlt,
                      border: Border(
                        left: BorderSide(color: ringColor, width: 2),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      _pretty,
                      style: mono(
                        size: 22,
                        color: TermColors.textBright,
                        weight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _CountdownRing(
                remaining: _remaining,
                period: period,
                color: ringColor,
              ),
              _CopyIcon(onTap: () => copyWithFlash(context, _code, 'code')),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small circular countdown that drains over the code's period.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.remaining,
    required this.period,
    required this.color,
  });
  final int remaining;
  final int period;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final frac = period <= 0 ? 0.0 : remaining / period;
    return Tooltip(
      message: 'refreshes in ${remaining}s',
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                value: frac.clamp(0.0, 1.0),
                strokeWidth: 2.5,
                backgroundColor: TermColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Text('$remaining', style: mono(size: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

class _CopyIcon extends StatelessWidget {
  const _CopyIcon({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Copy code',
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
              Icons.content_copy_outlined,
              size: 18,
              color: TermColors.textDim,
            ),
          ),
        ),
      );
}
