import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Database _sample() {
  final entry = Entry(
    uuid: 'ENTRY-UUID-1',
    fields: {
      Field.title: Field(
          key: Field.title, value: InMemoryProtectedValue.plain('GitHub'),),
      Field.userName: Field(
          key: Field.userName, value: InMemoryProtectedValue.plain('octocat'),),
      Field.password:
          Field(key: Field.password, value: InMemoryProtectedValue('s3cr3t!')),
      'API Token':
          Field(key: 'API Token', value: InMemoryProtectedValue('tok-123')),
    },
    tags: ['dev', 'work'],
    attachments: [Attachment(id: 'b1', name: 'key.pem', size: 4)],
    iconId: 12,
    created: DateTime.utc(2024, 1, 2, 3, 4, 5),
    modified: DateTime.utc(2024, 6, 7, 8, 9, 10),
  );
  // A prior version in history.
  entry.history.add(Entry(
    uuid: 'ENTRY-UUID-1',
    fields: {
      Field.password:
          Field(key: Field.password, value: InMemoryProtectedValue('old-pw')),
    },
  ),);

  final child = Group(uuid: 'G2', name: 'Servers', entries: [entry]);
  final root = Group(
    uuid: 'G1',
    name: 'Root',
    notes: 'top level',
    groups: [child],
  );
  return Database(
    meta: DatabaseMeta(name: 'Vault', description: 'test db'),
    root: root,
    binaryPool: [
      Attachment(id: 'b1', name: '', size: 4, inlineData: Uint8List.fromList([1, 2, 3, 4])),
    ],
  );
}

void main() {
  const codec = KeePassXml();

  test('round-trips database/meta', () {
    final db = _sample();
    final back = codec.decode(codec.encode(db));
    expect(back.meta.name, 'Vault');
    expect(back.meta.description, 'test db');
    expect(back.root.uuid, 'G1');
    expect(back.root.name, 'Root');
    expect(back.root.notes, 'top level');
    expect(back.root.groups.single.name, 'Servers');
  });

  test('round-trips history limits (defaults + custom)', () {
    final back = codec.decode(codec.encode(_sample()));
    expect(back.meta.historyMaxItems, 10); // defaults
    expect(back.meta.historyMaxSize, 6 * 1024 * 1024);

    final db = _sample();
    db.meta.historyMaxItems = 25;
    db.meta.historyMaxSize = 2 * 1024 * 1024;
    final back2 = codec.decode(codec.encode(db));
    expect(back2.meta.historyMaxItems, 25);
    expect(back2.meta.historyMaxSize, 2 * 1024 * 1024);
  });

  test('round-trips MasterKeyChanged (absent, then stamped)', () {
    // A vault that predates the field stays null rather than inventing a date.
    final fresh = codec.decode(codec.encode(_sample()));
    expect(fresh.meta.masterKeyChanged, isNull);
    expect(codec.encode(_sample()), isNot(contains('MasterKeyChanged')));

    final db = _sample();
    final stamp = DateTime.utc(2026, 8, 29, 14, 30, 15);
    db.meta.masterKeyChanged = stamp;
    final xml = codec.encode(db);
    expect(xml, contains('<MasterKeyChanged>'));

    final back = codec.decode(xml);
    expect(back.meta.masterKeyChanged, stamp);
    expect(back.meta.masterKeyChanged!.isUtc, isTrue);
  });

  test('reads the KDBX4 binary time form written by KeePass/KeePassXC', () {
    // base64 of a little-endian int64: seconds since 0001-01-01T00:00:00Z.
    final expected = DateTime.utc(2026, 8, 29, 14, 30, 15);
    final seconds = expected.difference(DateTime.utc(1, 1, 1)).inSeconds;
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setInt64(0, seconds, Endian.little);
    final encoded = base64.encode(bytes);

    final xml = codec.encode(_sample()).replaceFirst(
          '</Meta>',
          '<MasterKeyChanged>$encoded</MasterKeyChanged></Meta>',
        );
    expect(codec.decode(xml).meta.masterKeyChanged, expected);

    // Junk in a time element is ignored, not fatal.
    final junk = codec.encode(_sample()).replaceFirst('</Meta>',
        '<MasterKeyChanged>not-a-time</MasterKeyChanged></Meta>',);
    expect(codec.decode(junk).meta.masterKeyChanged, isNull);
  });

  test('round-trips entry fields incl. protected + custom', () {
    final db = _sample();
    final back = codec.decode(codec.encode(db));
    final e = back.root.groups.single.entries.single;

    expect(e.uuid, 'ENTRY-UUID-1');
    expect(e.fields[Field.title]!.value.reveal(), 'GitHub');
    expect(e.fields[Field.userName]!.value.reveal(), 'octocat');
    expect(e.fields[Field.password]!.value.reveal(), 's3cr3t!');
    expect(e.fields[Field.password]!.isProtected, isTrue);
    expect(e.fields[Field.title]!.isProtected, isFalse);

    // Custom protected field preserved with its protection flag.
    expect(e.fields['API Token']!.value.reveal(), 'tok-123');
    expect(e.fields['API Token']!.isProtected, isTrue);
    expect(e.fields['API Token']!.isCustom, isTrue);
  });

  test('round-trips tags, icon, and times', () {
    final db = _sample();
    final e =
        codec.decode(codec.encode(db)).root.groups.single.entries.single;
    expect(e.tags, ['dev', 'work']);
    expect(e.iconId, 12);
    expect(e.created, DateTime.utc(2024, 1, 2, 3, 4, 5));
    expect(e.modified, DateTime.utc(2024, 6, 7, 8, 9, 10));
  });

  test('round-trips attachment refs and the binary pool', () {
    final db = _sample();
    final back = codec.decode(codec.encode(db));
    final e = back.root.groups.single.entries.single;
    expect(e.attachments.single.id, 'b1');
    expect(e.attachments.single.name, 'key.pem');

    final pooled = back.binaryPool.single;
    expect(pooled.id, 'b1');
    expect(pooled.inlineData, [1, 2, 3, 4]);
  });

  test('round-trips entry history (flat, no nested history)', () {
    final db = _sample();
    final e =
        codec.decode(codec.encode(db)).root.groups.single.entries.single;
    expect(e.history.single.fields[Field.password]!.value.reveal(), 'old-pw');
    expect(e.history.single.history, isEmpty);
  });

  test('produces well-formed XML with a KeePassFile root', () {
    final xml = codec.encode(_sample());
    expect(xml, contains('<KeePassFile>'));
    expect(xml, contains('<DatabaseName>Vault</DatabaseName>'));
    expect(xml, contains('Protected="True"'));
  });
}
