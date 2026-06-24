// dgvault — remote storage abstraction for cloud sync.
//
// A minimal blob store keyed by path. The concrete adapters (OneDrive, Google
// Drive, Dropbox, iCloud, SFTP, WebDAV, Nextcloud, SharePoint) are account- and
// network-gated and live in the platform layer; the sync engine depends only on
// this interface and is fully testable with the in-memory fake.

import 'dart:typed_data';

/// Lightweight remote-object metadata for change detection (optional use).
class RemoteMetadata {
  const RemoteMetadata({this.etag, this.modified, this.size});
  final String? etag;
  final DateTime? modified;
  final int? size;
}

abstract interface class RemoteStorage {
  Future<bool> exists(String path);
  Future<Uint8List> download(String path);
  Future<void> upload(String path, Uint8List data);
  Future<RemoteMetadata?> stat(String path);
}

class RemoteStorageException implements Exception {
  RemoteStorageException(this.message);
  final String message;
  @override
  String toString() => 'RemoteStorageException: $message';
}

/// In-memory fake for tests / sessions without a configured provider.
class InMemoryRemoteStorage implements RemoteStorage {
  final Map<String, Uint8List> _store = {};
  final Map<String, DateTime> _modified = {};

  /// Monotonic counter stands in for a provider clock (no Date.now in core).
  int _tick = 0;

  @override
  Future<bool> exists(String path) async => _store.containsKey(path);

  @override
  Future<Uint8List> download(String path) async {
    final data = _store[path];
    if (data == null) {
      throw RemoteStorageException('no remote object at "$path"');
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<void> upload(String path, Uint8List data) async {
    _store[path] = Uint8List.fromList(data);
    _modified[path] = DateTime.fromMillisecondsSinceEpoch(_tick++);
  }

  @override
  Future<RemoteMetadata?> stat(String path) async {
    final data = _store[path];
    if (data == null) return null;
    return RemoteMetadata(
      etag: '${data.length}-${_modified[path]?.millisecondsSinceEpoch}',
      modified: _modified[path],
      size: data.length,
    );
  }
}
