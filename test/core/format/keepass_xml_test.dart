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
