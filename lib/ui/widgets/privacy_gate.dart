// dgvault — privacy overlay for backgrounding.
//
// When the app leaves the foreground (inactive / paused / hidden) the OS may
// snapshot the current window for the app switcher / recents. On Android
// FLAG_SECURE already blanks that snapshot; iOS has no equivalent flag, so we
// cover the UI with an opaque overlay the moment we go inactive and remove it on
// resume. This is a pure Flutter-side hook (no native iOS code) and is harmless
// on other platforms. The clock/lifecycle are observed via WidgetsBinding so it
// is drivable from a widget test.

import 'package:flutter/widgets.dart';

import '../theme/terminal_theme.dart';

class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cover for anything that isn't the foreground; uncover on resume. The
    // overlay is raised on `inactive` (which precedes the OS snapshot) so the
    // switcher/recents thumbnail never captures vault contents.
    final cover = state != AppLifecycleState.resumed;
    if (cover != _covered) setState(() => _covered = cover);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_covered)
          const Positioned.fill(
            child: _PrivacyCurtain(),
          ),
      ],
    );
  }
}

class _PrivacyCurtain extends StatelessWidget {
  const _PrivacyCurtain();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TermColors.bg,
      child: Center(
        child: Text(
          'dgvault',
          style: mono(size: 18, color: TermColors.green, letterSpacing: 4),
        ),
      ),
    );
  }
}
