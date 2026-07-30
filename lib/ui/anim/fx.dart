// dgvault — "FX": demoscene-style UI motion. Elements fly in from random
// directions, zoom, spin, warp and shimmer as screens populate, folders switch
// and buttons are pressed. Purely cosmetic and globally toggleable (Settings →
// "Screen effects"), on by default. When off, every helper here renders its
// child with zero overhead.
//
// The look is coordinated per "batch": when a list/screen (re)populates a
// single random [FxStyle] is chosen for the whole batch (so sometimes every row
// flies in from the left, sometimes each scatters from its own direction),
// staggered by index for that classic cracktro cascade.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Global on/off for all screen effects, persisted app-wide. Default: on.
class Fx {
  Fx._();
  static final Fx instance = Fx._();

  static const _fileName = 'app_settings.json';

  /// Listen to rebuild the UI when the user toggles effects.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  final Random _rng = Random();

  bool get on => enabled.value;

  /// Load the persisted preference (call once at startup). Never throws.
  Future<void> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final data = jsonDecode(await f.readAsString());
      if (data is Map && data['fx'] is bool) {
        enabled.value = data['fx'] as bool;
      }
    } catch (_) {
      // Missing/corrupt → keep the default.
    }
  }

  Future<void> set(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    try {
      await (await _file()).writeAsString(jsonEncode({'fx': value}));
    } catch (_) {
      // Best-effort; the in-memory value still applies this session.
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// A fresh random batch for the next population of a list/screen.
  FxBatch nextBatch() => FxBatch(
        style: FxStyle.values[_rng.nextInt(FxStyle.values.length)],
        seed: _rng.nextInt(1 << 30),
      );

  /// A random entrance for a one-off surface (a sheet, a pushed screen).
  FxStyle randomStyle() =>
      FxStyle.values[_rng.nextInt(FxStyle.values.length)];
}

/// The entrance flavours. A batch picks one; [scatter] then varies per element.
enum FxStyle {
  fromLeft,
  fromRight,
  fromTop,
  fromBottom,
  scatter, // each element from its own random direction
  zoomIn, // grows in from far away (toward the user)
  zoomOut, // rushes in from in front (away from the user, settling back)
  spin,
  warp,
  shimmer,
}

/// A coordinated entrance for one population pass: the shared [style] plus a
/// [seed] so per-element randomness (scatter directions, shimmer phase) is
/// stable across rebuilds while the animation plays.
@immutable
class FxBatch {
  const FxBatch({required this.style, required this.seed});
  final FxStyle style;
  final int seed;
}

/// Inherited [FxBatch] read by [FlyIn] descendants. Changing the batch's seed
/// re-triggers their entrance (so a re-sort or folder switch re-cascades).
class FlyInScope extends InheritedWidget {
  const FlyInScope({super.key, required this.batch, required super.child});
  final FxBatch batch;

  static FxBatch? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FlyInScope>()
      ?.batch;

  @override
  bool updateShouldNotify(FlyInScope old) =>
      old.batch.seed != batch.seed || old.batch.style != batch.style;
}

/// Wraps [child] and plays a staggered entrance the first time it mounts (and
/// again whenever the enclosing [FlyInScope] batch changes). [index] drives the
/// stagger. Pass an explicit [style] to bypass the scope (one-off surfaces).
/// A no-op passthrough when effects are disabled.
class FlyIn extends StatefulWidget {
  const FlyIn({
    super.key,
    required this.child,
    this.index = 0,
    this.style,
    this.duration = const Duration(milliseconds: 380),
    this.stagger = const Duration(milliseconds: 22),
    this.maxStagger = const Duration(milliseconds: 320),
  });

  final Widget child;
  final int index;
  final FxStyle? style;
  final Duration duration;
  final Duration stagger;
  final Duration maxStagger;

  @override
  State<FlyIn> createState() => _FlyInState();
}

class _FlyInState extends State<FlyIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _delay;
  int _seed = 0;
  FxStyle _style = FxStyle.fromLeft;
  bool _armed = false; // has an entrance been scheduled/played yet?

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Fx.instance.on) return;
    final batch = widget.style != null
        ? FxBatch(style: widget.style!, seed: 0)
        : FlyInScope.of(context);
    if (batch == null) return;
    final style = widget.style ?? batch.style;
    if (!_armed || batch.seed != _seed || style != _style) {
      _seed = batch.seed;
      _style = style;
      _armed = true;
      _play();
    }
  }

  void _play() {
    _delay?.cancel();
    _c.value = 0;
    // easeOutBack overshoots — nice for the "punch" of zoom/spin entrances.
    final overshoot = _style == FxStyle.zoomIn ||
        _style == FxStyle.zoomOut ||
        _style == FxStyle.spin;
    _t = CurvedAnimation(
      parent: _c,
      curve: overshoot ? Curves.easeOutBack : Curves.easeOutCubic,
    );
    final d = Duration(
      milliseconds: min(
        widget.maxStagger.inMilliseconds,
        widget.index * widget.stagger.inMilliseconds,
      ),
    );
    _delay = Timer(d, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Fx.instance.on || !_armed) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final t = _t.value.clamp(-0.5, 1.5);
        return _transformFor(_style, t, _seed, widget.index, child!);
      },
      child: widget.child,
    );
  }
}

const double _flyDistance = 380;
const double _twoPi = pi * 2;

/// A deterministic unit-ish vector for element [index] within [seed] — used by
/// [FxStyle.scatter] so each element keeps its own direction across frames.
Offset _scatterDir(int seed, int index) {
  final h = (seed * 73856093) ^ (index * 19349663) ^ 0x9E3779B9;
  final a = (h & 0xffff) / 0xffff * _twoPi;
  return Offset(cos(a), sin(a));
}

double _hash01(int seed, int index, int salt) {
  final h = (seed * 40503) ^ (index * 2654435761) ^ (salt * 2246822519);
  return (h & 0x7fffffff) / 0x7fffffff;
}

Widget _transformFor(
  FxStyle style,
  double t,
  int seed,
  int index,
  Widget child,
) {
  final inv = 1 - t; // 1 at start, 0 when settled
  final fade = (t * 1.6).clamp(0.0, 1.0);

  switch (style) {
    case FxStyle.fromLeft:
      return _slide(Offset(-_flyDistance * inv, 0), fade, child);
    case FxStyle.fromRight:
      return _slide(Offset(_flyDistance * inv, 0), fade, child);
    case FxStyle.fromTop:
      return _slide(Offset(0, -_flyDistance * inv), fade, child);
    case FxStyle.fromBottom:
      return _slide(Offset(0, _flyDistance * inv), fade, child);
    case FxStyle.scatter:
      final dir = _scatterDir(seed, index);
      return _slide(dir * _flyDistance * inv, fade, child);
    case FxStyle.zoomIn:
      return Opacity(
        opacity: fade,
        child: Transform.scale(scale: (0.15 + 0.85 * t).clamp(0.02, 4.0), child: child),
      );
    case FxStyle.zoomOut:
      return Opacity(
        opacity: fade,
        child: Transform.scale(scale: (2.8 - 1.8 * t).clamp(0.02, 4.0), child: child),
      );
    case FxStyle.spin:
      final dir = _hash01(seed, index, 7) < 0.5 ? -1.0 : 1.0;
      return Opacity(
        opacity: fade,
        child: Transform.rotate(
          angle: dir * _twoPi * 1.15 * inv,
          child: Transform.scale(scale: (0.3 + 0.7 * t).clamp(0.02, 4.0), child: child),
        ),
      );
    case FxStyle.warp:
      final dir = _hash01(seed, index, 3) < 0.5 ? -1.0 : 1.0;
      final m = Matrix4.identity()
        ..setEntry(3, 2, 0.0015) // perspective
        ..rotateY(dir * 1.4 * inv)
        ..rotateX(0.5 * inv);
      return Opacity(
        opacity: fade,
        child: Transform(
          alignment: Alignment.center,
          transform: m,
          child: Transform.scale(scale: (0.55 + 0.45 * t).clamp(0.02, 4.0), child: child),
        ),
      );
    case FxStyle.shimmer:
      // Slide up a touch while flickering opacity a few times.
      final flick = 0.55 + 0.45 * sin(t * pi * 5).abs();
      return Opacity(
        opacity: (fade * flick).clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 10 * inv), child: child),
      );
  }
}

Widget _slide(Offset off, double opacity, Widget child) => Opacity(
      opacity: opacity,
      child: Transform.translate(offset: off, child: child),
    );

/// Wraps a tappable [child] with a quick press "punch" (scale down on press,
/// spring back on release). Does NOT intercept taps — the child's own gesture
/// handling still fires. No-op when effects are off.
class FxTap extends StatefulWidget {
  const FxTap({super.key, required this.child});
  final Widget child;

  @override
  State<FxTap> createState() => _FxTapState();
}

class _FxTapState extends State<FxTap> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 260),
    value: 0,
  );
  late final Animation<double> _scale =
      Tween<double>(begin: 1, end: 0.86).animate(
    CurvedAnimation(
      parent: _c,
      curve: Curves.easeOut,
      reverseCurve: Curves.elasticOut,
    ),
  );

  void _down() {
    if (Fx.instance.on) _c.forward();
  }

  void _up() {
    if (Fx.instance.on) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Fx.instance.on) return widget.child;
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// A page route whose push/pop transition is a random zoom/warp/spin — for the
/// "flying toward / away from the user" feel when entering and leaving a screen.
/// Falls back to a plain fade when effects are off.
Route<T> fxRoute<T>(Widget page) {
  final fx = Fx.instance.on;
  final style = fx ? Fx.instance.randomStyle() : FxStyle.zoomIn;
  return PageRouteBuilder<T>(
    transitionDuration: Duration(milliseconds: fx ? 360 : 200),
    reverseTransitionDuration: Duration(milliseconds: fx ? 300 : 160),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      if (!fx) return FadeTransition(opacity: anim, child: child);
      final t = Curves.easeOutCubic.transform(anim.value);
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: _transformFor(style, t, 1, 0, child),
      );
    },
  );
}
