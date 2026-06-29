// dgvault — the figlet wordmark, shared by the landing + unlock screens.

import 'package:flutter/material.dart';

import '../theme/terminal_theme.dart';

const String kDgvaultBanner = r'''
    _                    _ _
 __| |__ ___ ____ _ _  _| | |_
/ _` / _` \ V / _` | || | |  _|
\__,_\__, |\_/\__,_|\_,_|_|\__|
     |___/
     secure vault · kdbx4 · zero-knowledge''';

class BannerLogo extends StatelessWidget {
  const BannerLogo({super.key});

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          kDgvaultBanner,
          style: mono(size: 13, color: TermColors.green, height: 1.25),
        ),
      );
}
