// dgvault — cloud sync engine (transport- and codec-agnostic).
//
// Convergent sync over any [RemoteStorage] using the KeePass-style last-write-
// wins [DatabaseMerger]:
//   • first sync (no remote object) → push the local database.
//   • otherwise → download + decode the remote, merge it INTO local (LWW by
//     `modified`; remote-newer entries overwrite, local-only/newer survive,
//     deletions are NOT propagated), then upload the merged local back.
// After a successful sync both sides hold the union, so repeated syncs converge.
//
// [encode]/[decode] are injected (real `KdbxCodec` in production), so this is
// pure orchestration and unit-testable. Concrete providers implement
// [RemoteStorage] in the platform layer.

import 'dart:typed_data';

import '../../core/diff/database_diff.dart';
import '../../core/model/database.dart';
import 'remote_storage.dart';

typedef DatabaseDecoder = Future<Database> Function(Uint8List bytes);
typedef DatabaseEncoder = Future<Uint8List> Function(Database db);

enum SyncAction { pushedFirst, merged, alreadyInSync }

class SyncResult {
  const SyncResult({
    required this.action,
    this.addedFromRemote = const [],
    this.updatedFromRemote = const [],
  });

  final SyncAction action;

  /// Entry UUIDs pulled in from the remote.
  final List<String> addedFromRemote;

  /// Entry UUIDs whose local content the remote overwrote (remote was newer).
  final List<String> updatedFromRemote;

  bool get changedLocal =>
      addedFromRemote.isNotEmpty || updatedFromRemote.isNotEmpty;
}

class SyncEngine {
  SyncEngine({required this.remote, DatabaseMerger? merger})
      : merger = merger ?? const DatabaseMerger();

  final RemoteStorage remote;
  final DatabaseMerger merger;

  /// Sync [local] against the remote object at [path]. Mutates [local] in place
  /// with anything merged from the remote, and writes the merged result back.
  Future<SyncResult> sync({
    required String path,
    required Database local,
    required DatabaseDecoder decode,
    required DatabaseEncoder encode,
  }) async {
    if (!await remote.exists(path)) {
      await remote.upload(path, await encode(local));
      return const SyncResult(action: SyncAction.pushedFirst);
    }

    final remoteDb = await decode(await remote.download(path));
    final merged = merger.merge(local, remoteDb); // remote → local (LWW)

    // Push the union back so the remote converges with local.
    await remote.upload(path, await encode(local));

    return SyncResult(
      action: merged.added.isEmpty && merged.updated.isEmpty
          ? SyncAction.alreadyInSync
          : SyncAction.merged,
      addedFromRemote: merged.added,
      updatedFromRemote: merged.updated,
    );
  }
}
