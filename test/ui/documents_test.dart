// The in-place document bridge classifies which vault "locations" must be
// read/written natively (Android SAF URIs / iOS bookmarks) vs. via dart:io.

import 'package:dgvault/ui/state/documents.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isDocumentUri recognises Android SAF and iOS bookmark tokens', () {
    expect(
      Documents.isDocumentUri('content://com.android.providers/doc/1'),
      isTrue,
    );
    expect(Documents.isDocumentUri('bookmark:Ym9va21hcmtkYXRh'), isTrue);
    // Plain filesystem paths are written with dart:io, not the bridge.
    expect(Documents.isDocumentUri('/Users/x/vault.kdbx'), isFalse);
    expect(Documents.isDocumentUri('/sdcard/Download/vault.kdbx'), isFalse);
    expect(Documents.isDocumentUri('file:///tmp/vault.kdbx'), isFalse);
  });

  test('isSupported on mobile, not on desktop', () {
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = p;
      expect(Documents.isSupported, isTrue, reason: '$p');
    }
    for (final p in [
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      expect(Documents.isSupported, isFalse, reason: '$p');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('bookmarksRecents only on macOS (sandbox needs security-scoped reopen)',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(Documents.bookmarksRecents, isTrue);
    for (final p in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      expect(Documents.bookmarksRecents, isFalse, reason: '$p');
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
