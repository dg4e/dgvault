// dgvault — clipboard auto-clear wiring (platform side).
//
// Bridges the pure, unit-tested [ClipboardClearController] to a real timer and
// the system clipboard. When a secret is copied it schedules a wipe after the
// timeout; when the timer fires it clears the clipboard ONLY if it still holds
// exactly the value we put there (so it never clobbers something the user copied
// in the meantime). Locking the vault clears immediately, subject to the same
// guard. All clipboard I/O is injectable so this is testable without a platform.

import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/security/clipboard_autoclear.dart';

/// Reads/writes the system clipboard. Overridable in tests.
class ClipboardIo {
  const ClipboardIo();

  Future<void> setText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<String?> getText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}

/// App-wide clipboard auto-clear service. A single instance is shared so that a
/// newer copy supersedes the pending clear of an older one (the controller's
/// generation guard), and so `lock()` can wipe whatever the last copy was.
class ClipboardService {
  ClipboardService({
    Duration timeout = const Duration(seconds: 30),
    ClipboardIo io = const ClipboardIo(),
    DateTime Function() now = DateTime.now,
    Future<void> Function(Duration, void Function())? scheduler,
  })  : _controller = ClipboardClearController(timeout: timeout),
        _io = io,
        _now = now,
        _schedule = scheduler ?? _defaultScheduler;

  final ClipboardClearController _controller;
  final ClipboardIo _io;
  final DateTime Function() _now;
  final Future<void> Function(Duration, void Function()) _schedule;

  /// The last secret we wrote; used to guard the wipe so we never clear a value
  /// the user copied after us.
  String? _lastCopied;

  static Future<void> _defaultScheduler(
    Duration d,
    void Function() cb,
  ) async {
    Timer(d, cb);
  }

  /// Copy [value] to the clipboard and schedule an auto-clear.
  Future<void> copy(String value) async {
    await _io.setText(value);
    _lastCopied = value;
    final copy = _controller.copy(_now());
    await _schedule(copy.remaining(_now()), () {
      _clearIfCurrent(copy);
    });
  }

  Future<void> _clearIfCurrent(ClipboardCopy copy) async {
    if (!_controller.shouldClear(copy, _now())) return;
    await _wipeIfStillOurs();
  }

  /// Clear the clipboard immediately (e.g. on lock), guarded so it only wipes if
  /// the clipboard still holds the secret we last put there.
  Future<void> clearNow() async {
    _controller.cancel(); // any pending timer becomes non-current
    await _wipeIfStillOurs();
  }

  Future<void> _wipeIfStillOurs() async {
    final ours = _lastCopied;
    if (ours == null) return;
    final current = await _io.getText();
    // Only wipe if the clipboard still contains exactly our secret.
    if (current == ours) {
      await _io.setText('');
    }
    _lastCopied = null;
  }
}
