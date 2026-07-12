// The clipboard auto-clear wiring: a copied secret is scheduled for a wipe and
// cleared on lock, but a value the user copied AFTER us is never clobbered.

import 'package:dgvault/ui/state/clipboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory clipboard so we can drive it without a platform.
class _FakeIo implements ClipboardIo {
  String? text;
  @override
  Future<void> setText(String value) async => text = value;
  @override
  Future<String?> getText() async => text;
}

void main() {
  // A scheduler that captures the callback instead of using a real Timer, so we
  // can fire the "timeout" by hand and drive [now] deterministically.
  late void Function() fired;
  late DateTime now;
  ClipboardService make(_FakeIo io) {
    now = DateTime.utc(2026, 1, 1, 12);
    return ClipboardService(
      timeout: const Duration(seconds: 30),
      io: io,
      now: () => now,
      scheduler: (_, cb) async => fired = cb,
    );
  }

  test('a copy schedules a clear that wipes the secret at timeout', () async {
    final io = _FakeIo();
    final svc = make(io);

    await svc.copy('s3cret');
    expect(io.text, 's3cret'); // on the clipboard

    now = now.add(const Duration(seconds: 30)); // timeout elapses
    fired();
    await Future<void>.delayed(Duration.zero);

    expect(io.text, ''); // wiped
  });

  test('a clipboard changed by the user is NOT wiped', () async {
    final io = _FakeIo();
    final svc = make(io);

    await svc.copy('s3cret');
    io.text = 'user copied something else'; // user copies afterwards

    now = now.add(const Duration(seconds: 30));
    fired();
    await Future<void>.delayed(Duration.zero);

    // The guard compares current clipboard to our secret — mismatch → left alone.
    expect(io.text, 'user copied something else');
  });

  test('clearNow wipes our secret immediately (guarded)', () async {
    final io = _FakeIo();
    final svc = make(io);

    await svc.copy('s3cret');
    await svc.clearNow();
    expect(io.text, '');
  });

  test('clearNow does not clobber a user-copied value', () async {
    final io = _FakeIo();
    final svc = make(io);

    await svc.copy('s3cret');
    io.text = 'other';
    await svc.clearNow();
    expect(io.text, 'other');
  });

  test('a stale timer does not wipe a newer copy', () async {
    final io = _FakeIo();
    final svc = make(io);

    await svc.copy('first');
    final firstTimer = fired;
    await svc.copy('second'); // supersedes the first
    now = now.add(const Duration(seconds: 30));

    firstTimer(); // the OLD timer fires late
    await Future<void>.delayed(Duration.zero);
    expect(io.text, 'second', reason: 'stale timer must not wipe newer secret');
  });
}
