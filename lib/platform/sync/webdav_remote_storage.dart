// dgvault — WebDAV RemoteStorage adapter (Nextcloud / generic WebDAV / SFTP-over-
// HTTP gateways). A concrete [RemoteStorage] for the SyncEngine over plain HTTP:
// GET to download, PUT to upload, HEAD/PROPFIND to test existence.
//
// NETWORK-GATED: needs a live WebDAV server + credentials, so it is exercised in
// integration tests, not unit tests. The convergence/merge logic it feeds is
// fully tested in core via `InMemoryRemoteStorage`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/data/sync/remote_storage.dart';
import 'package:http/http.dart' as http;

class WebDavRemoteStorage implements RemoteStorage {
  WebDavRemoteStorage({
    required Uri baseUrl,
    String? username,
    String? password,
    http.Client? client,
  })  : _base = baseUrl,
        _client = client ?? http.Client(),
        _authHeader = (username != null && password != null)
            ? 'Basic ${base64Auth(username, password)}'
            : null;

  final Uri _base;
  final http.Client _client;
  final String? _authHeader;

  Uri _uri(String path) => _base.resolve(path);
  Map<String, String> get _headers =>
      _authHeader == null ? {} : {'authorization': _authHeader};

  @override
  Future<bool> exists(String path) async {
    final res = await _client.head(_uri(path), headers: _headers);
    if (res.statusCode == 200) return true;
    if (res.statusCode == 404) return false;
    throw RemoteStorageException('HEAD $path → ${res.statusCode}');
  }

  @override
  Future<Uint8List> download(String path) async {
    final res = await _client.get(_uri(path), headers: _headers);
    if (res.statusCode != 200) {
      throw RemoteStorageException('GET $path → ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  @override
  Future<void> upload(String path, Uint8List data) async {
    final res = await _client.put(_uri(path), headers: _headers, body: data);
    if (res.statusCode ~/ 100 != 2) {
      throw RemoteStorageException('PUT $path → ${res.statusCode}');
    }
  }

  @override
  Future<RemoteMetadata?> stat(String path) async {
    final res = await _client.head(_uri(path), headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw RemoteStorageException('HEAD $path → ${res.statusCode}');
    }
    final len = int.tryParse(res.headers['content-length'] ?? '');
    return RemoteMetadata(etag: res.headers['etag'], size: len);
  }
}

/// Base64 of `user:pass` for HTTP Basic auth.
String base64Auth(String user, String pass) =>
    base64.encode(utf8.encode('$user:$pass'));
