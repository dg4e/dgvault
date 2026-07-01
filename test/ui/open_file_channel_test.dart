// The native runners deliver an opened .kdbx as {name, bytes} over the
// dgvault/open_file channel; OpenFileChannel must load it into the controller.

import 'package:dgvault/ui/state/open_file_channel.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dgvault/open_file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Desktop path: bytes load directly (mobile would import via path_provider,
  // which is covered on-device; the pure import helpers are in file_service_test).
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('start() loads the initial file (bytes) → locked unlock screen', () async {
    final bytes = await buildTestVaultBytes();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getInitialFile') {
        return {'name': 'opened.kdbx', 'bytes': bytes};
      }
      return null;
    });

    final c = VaultController();
    await OpenFileChannel(c).start();

    expect(c.status, VaultStatus.locked);
    expect(c.fileName, 'opened.kdbx');
  });

  test('start() with no initial file leaves the controller idle', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final c = VaultController();
    await OpenFileChannel(c).start();
    expect(c.status, VaultStatus.noVault);
  });

  test('iOS in-place open: a bookmark path loads without importing a copy',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final bytes = await buildTestVaultBytes();
    // A security-scoped bookmark token → save writes back to the original, so
    // the controller keeps the token as its path (no path_provider import).
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getInitialFile') {
        return {
          'name': 'inplace.kdbx',
          'bytes': bytes,
          'path': 'bookmark:Ym9va21hcmtkYXRh',
        };
      }
      return null;
    });

    final c = VaultController();
    await OpenFileChannel(c).start();

    expect(c.status, VaultStatus.locked);
    expect(c.fileName, 'inplace.kdbx');
    expect(c.path, 'bookmark:Ym9va21hcmtkYXRh');
  });

  test('a pushed openFile call loads the vault while running', () async {
    final bytes = await buildTestVaultBytes();
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final c = VaultController();
    await OpenFileChannel(c).start();
    expect(c.status, VaultStatus.noVault);

    // Simulate the native side pushing a file (warm start).
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        MethodCall('openFile', {'name': 'pushed.kdbx', 'bytes': bytes}),
      ),
      (_) {},
    );

    expect(c.status, VaultStatus.locked);
    expect(c.fileName, 'pushed.kdbx');
  });
}
