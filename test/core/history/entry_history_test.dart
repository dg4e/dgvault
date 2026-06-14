import 'dart:typed_data';

import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/attachment.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/core/history/entry_history.dart';
import 'package:test/test.dart';

Entry entryWith(String title, {List<Attachment> attachments = const []}) {
  return Entry(
    uuid: 'u1',
    fields: {
      Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain(title)),
    },
    attachments: List.of(attachments),
  );
}

void setTitle(Entry e, String title) {
  e.fields[Field.title] =
      Field(key: Field.title, value: InMemoryProtectedValue.plain(title));
}

void main() {
  group('snapshot', () {
    test('deep-copies content and carries no nested history', () {
      final e = entryWith('orig');
      final snap = EntryHistoryService.snapshot(e);
      expect(snap.title, 'orig');
      expect(snap.history, isEmpty);
      // Mutating the original must not affect the snapshot.
      setTitle(e, 'changed');
      expect(e.title, 'changed');
      expect(snap.title, 'orig');
    });
  });

  group('record', () {
    test('captures pre-edit state and bumps modified', () {
      final svc = EntryHistoryService();
      final e = entryWith('v1');
      final now = DateTime.utc(2026, 6, 14);
      svc.record(e, now: now);
      expect(e.history, hasLength(1));
      expect(e.history.first.title, 'v1');
      expect(e.modified, now);
      // Edit after recording does not alter the stored version.
      setTitle(e, 'v2');
      expect(e.history.first.title, 'v1');
    });

    test('extension pushHistory works', () {
      final e = entryWith('a');
      expect(e.pushHistory(), 1);
      expect(e.history, hasLength(1));
    });
  });

  group('prune', () {
    test('enforces maxItems (drops oldest first)', () {
      final svc = EntryHistoryService(
          policy: const HistoryPolicy(maxItems: 3, maxTotalSizeBytes: -1));
      final e = entryWith('x');
      for (var i = 0; i < 5; i++) {
        setTitle(e, 'v$i');
        svc.record(e);
      }
      expect(e.history, hasLength(3));
      // Oldest (v0, v1) dropped; newest retained.
      expect(e.history.map((h) => h.title), ['v2', 'v3', 'v4']);
    });

    test('enforces maxTotalSizeBytes (keeps at least one)', () {
      final att = Attachment(id: 'a', name: 'f', size: 600, inlineData: null);
      final svc = EntryHistoryService(
          policy: const HistoryPolicy(maxItems: -1, maxTotalSizeBytes: 1300));
      final e = entryWith('a', attachments: [att]); // ~612 bytes per version
      for (var i = 0; i < 5; i++) {
        svc.record(e);
      }
      // Two versions (~1224B) fit under 1300; a third would exceed it.
      expect(e.history, hasLength(2));
    });

    test('unlimited policy keeps everything', () {
      final svc = EntryHistoryService(policy: HistoryPolicy.unlimited);
      final e = entryWith('x');
      for (var i = 0; i < 25; i++) {
        svc.record(e);
      }
      expect(e.history, hasLength(25));
    });
  });

  group('restore', () {
    test('restores an old version and keeps current as new history', () {
      final svc = EntryHistoryService();
      final e = entryWith('v1');
      svc.record(e); // history: [v1]
      setTitle(e, 'v2');
      svc.restore(e, 0); // restore v1, snapshot v2
      expect(e.title, 'v1');
      // history now contains the original v1 plus the snapshotted v2.
      expect(e.history.map((h) => h.title), containsAll(['v1', 'v2']));
    });

    test('restore can skip keeping current state', () {
      final svc = EntryHistoryService();
      final e = entryWith('v1');
      svc.record(e);
      setTitle(e, 'v2');
      svc.restore(e, 0, keepCurrentInHistory: false);
      expect(e.title, 'v1');
      expect(e.history, hasLength(1)); // only the original v1
    });

    test('out-of-range index throws', () {
      final svc = EntryHistoryService();
      final e = entryWith('v1');
      svc.record(e);
      expect(() => svc.restore(e, 5), throwsA(isA<RangeError>()));
    });
  });

  group('versionSize + clear', () {
    test('counts field and attachment bytes', () {
      final att = Attachment(
          id: 'a', name: 'f', size: 1000, inlineData: Uint8List(0));
      final e = entryWith('ab', attachments: [att]); // 'Title'(10)+'ab'(4)=14 +1000
      expect(EntryHistoryService.versionSize(e), 1014);
    });

    test('clear empties history', () {
      final svc = EntryHistoryService();
      final e = entryWith('x');
      svc.record(e);
      svc.clear(e);
      expect(e.history, isEmpty);
    });
  });
}
