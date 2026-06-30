// dgvault — drives the AutoLockPolicy: re-locks the vault on inactivity or
// after the app has been out of focus. Wraps the whole app (via MaterialApp's
// builder) so it sees pointer activity across screens, dialogs, and sheets.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../state/vault_controller.dart';

class AutoLockGate extends StatefulWidget {
  const AutoLockGate({
    super.key,
    required this.controller,
    required this.child,
    this.now = DateTime.now, // injectable for tests
  });

  final VaultController controller;
  final Widget child;
  final DateTime Function() now;

  @override
  State<AutoLockGate> createState() => _AutoLockGateState();
}

class _AutoLockGateState extends State<AutoLockGate>
    with WidgetsBindingObserver {
  late DateTime _lastActivity = widget.now();
  DateTime? _focusLostAt;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idleTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _checkIdle());
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _markActivity() => _lastActivity = widget.now();

  void _checkIdle() {
    final c = widget.controller;
    if (!c.isUnlocked) return;
    if (c.autoLockPolicy.shouldLockOnIdle(_lastActivity, widget.now())) {
      c.lock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = widget.controller;
    switch (state) {
      case AppLifecycleState.resumed:
        final lostAt = _focusLostAt;
        _focusLostAt = null;
        if (c.isUnlocked &&
            lostAt != null &&
            c.autoLockPolicy.shouldLockOnRefocus(lostAt, widget.now())) {
          c.lock();
        }
        _markActivity();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Start the focus-lost clock the first time we leave the foreground.
        _focusLostAt ??= widget.now();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _markActivity(),
      onPointerMove: (_) => _markActivity(),
      onPointerSignal: (_) => _markActivity(),
      child: widget.child,
    );
  }
}
