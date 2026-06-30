// dgvault — the figlet wordmark, shared by the landing + unlock screens. The
// tagline under the wordmark is a random lowercase quote from "Hackers" (1995).

import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/terminal_theme.dart';

const String kDgvaultFiglet = r'''
    _                    _ _
 __| |__ ___ ____ _ _  _| | |_
/ _` / _` \ V / _` | || | |  _|
\__,_\__, |\_/\__,_|\_,_|_|\__|
     |___/''';

/// Short, iconic one-liners from the film "Hackers" (1995).
const List<String> kHackersQuotes = [
  'hack the planet!',
  'mess with the best, die like the rest.',
  "there is no right and wrong. there's only fun and boring.",
  'this is our world now.',
  "they're trashing our rights, man!",
  'rabbit is good. rabbit is wise.',
  "never send a boy to do a woman's job.",
  'crash and burn.',
  'you wanted to be elite.',
  "god, i hope i'm not a clone.",
  'the pool on the roof must have a leak.',
  'type cookie, you idiot.',
  "hacking is more than a crime. it's a survival trait.",
  'we are samurai. the keyboard cowboys.',
  'spans the globe!',
];

final Random _rng = Random();

class BannerLogo extends StatefulWidget {
  const BannerLogo({super.key});

  @override
  State<BannerLogo> createState() => _BannerLogoState();
}

class _BannerLogoState extends State<BannerLogo> {
  // Pick once per mount so it doesn't flicker on rebuilds.
  late final String _quote = kHackersQuotes[_rng.nextInt(kHackersQuotes.length)];

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              kDgvaultFiglet,
              style: mono(size: 13, color: TermColors.green, height: 1.25),
            ),
            const SizedBox(height: 6),
            Text(
              _quote,
              style: mono(size: 12, color: TermColors.greenDim),
            ),
          ],
        ),
      );
}
