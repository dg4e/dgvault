// Sync engine over a fake remote, using the REAL KdbxCodec (Argon2 + AES + HMAC
// stream) to encode/decode — a two-device convergence + conflict scenario.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';
import 'package:dgvault/data/sync/remote_storage.dart';
import 'package:dgvault/data/sync/sync_engine.dart';
import 'package:test/test.dart';

final _cred = CompositeCredential(password: Uint8List.fromList(utf8.encode('shared-pw')));
final _rng = Random(7);

KdbxCodec _codec() => KdbxCodec(
      bodyCipher: Kdbx4BodyCipher(kdf: const Argon2KeyDerivation()),
      compressor: const GzipCompressor(),
    );

KdbxHeader _freshHeader() {
  Uint8List rnd(int n) => Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));
  return KdbxHeader(
    cipher: DatabaseCipher.aes256,
    compressed: true,
    masterSeed: rnd(32),
    encryptionIv: rnd(16),
    kdfParameters: KdfParameters.toVariantDictionary(
      const KdfParams(algorithm: KdfAlgorithm.argon2id, iterations: 2, memoryKib: 64, parallelism: 1),
      rnd(16),
    ),
  );
}

Future<Uint8List> _encode(Database db) => _codec().write(db, _freshHeader(), _cred);
Future<Database> _decode(Uint8List bytes) => _codec().read(bytes, _cred);

Entry _entry(String uuid, String title, DateTime modified) => Entry(
      uuid: uuid,
      fields: {
        Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain(title)),
      },
      modified: modified,
    );

Database _db(List<Entry> entries) =>
    Database(meta: DatabaseMeta(name: 'V'), root: Group(uuid: 'R', name: 'Root', entries: entries));

String? _titleOf(Database db, String uuid) {
  for (final e in db.root.entries) {
    if (e.uuid == uuid) return e.fields[Field.title]?.value.reveal();
  }
  return null;
}

void main() {
  const path = 'vault.kdbx';

  test('first sync pushes; second device pulls + pushes the union; both converge',
      () async {
    final remote = InMemoryRemoteStorage();
    final engine = SyncEngine(remote: remote);

    final a = _db([_entry('e1', 'A-one', DateTime.utc(2026, 1, 1))]);
    final b = _db([_entry('e2', 'B-two', DateTime.utc(2026, 1, 2))]);

    final r1 = await engine.sync(path: path, local: a, decode: _decode, encode: _encode);
    expect(r1.action, SyncAction.pushedFirst);

    final r2 = await engine.sync(path: path, local: b, decode: _decode, encode: _encode);
    expect(r2.action, SyncAction.merged);
    expect(r2.addedFromRemote, contains('e1'));
    // B now holds both.
    expect(_titleOf(b, 'e1'), 'A-one');
    expect(_titleOf(b, 'e2'), 'B-two');

    // A syncs again and converges to the union too.
    await engine.sync(path: path, local: a, decode: _decode, encode: _encode);
    expect(_titleOf(a, 'e1'), 'A-one');
    expect(_titleOf(a, 'e2'), 'B-two');
  });

  test('a no-change re-sync reports alreadyInSync', () async {
    final remote = InMemoryRemoteStorage();
    final engine = SyncEngine(remote: remote);
    final a = _db([_entry('e1', 'one', DateTime.utc(2026, 1, 1))]);
    await engine.sync(path: path, local: a, decode: _decode, encode: _encode);
    final again = await engine.sync(path: path, local: a, decode: _decode, encode: _encode);
    expect(again.action, SyncAction.alreadyInSync);
    expect(again.changedLocal, isFalse);
  });

  test('conflict on the same UUID resolves last-write-wins (newer remote wins)',
      () async {
    final remote = InMemoryRemoteStorage();
    final engine = SyncEngine(remote: remote);

    // Remote has the newer version of e1.
    final newer = _db([_entry('e1', 'NEW', DateTime.utc(2026, 6, 1))]);
    await engine.sync(path: path, local: newer, decode: _decode, encode: _encode);

    // Local has an older version of the same entry.
    final older = _db([_entry('e1', 'OLD', DateTime.utc(2026, 1, 1))]);
    final r = await engine.sync(path: path, local: older, decode: _decode, encode: _encode);

    expect(r.updatedFromRemote, contains('e1'));
    expect(_titleOf(older, 'e1'), 'NEW', reason: 'newer remote overwrote local');
  });

  test('local-newer edit wins and is pushed to the remote', () async {
    final remote = InMemoryRemoteStorage();
    final engine = SyncEngine(remote: remote);

    final old = _db([_entry('e1', 'OLD', DateTime.utc(2026, 1, 1))]);
    await engine.sync(path: path, local: old, decode: _decode, encode: _encode);

    final local = _db([_entry('e1', 'LOCAL-NEW', DateTime.utc(2026, 6, 1))]);
    final r = await engine.sync(path: path, local: local, decode: _decode, encode: _encode);
    expect(r.updatedFromRemote, isEmpty, reason: 'local was newer; nothing pulled');
    expect(_titleOf(local, 'e1'), 'LOCAL-NEW');

    // The remote now carries the local-newer version.
    final remoteDb = await _decode(await remote.download(path));
    expect(_titleOf(remoteDb, 'e1'), 'LOCAL-NEW');
  });
}
