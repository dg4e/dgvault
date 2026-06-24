// WebDAV adapter mapped onto a mock HTTP server (no network). Verifies the
// RemoteStorage→HTTP mapping and drives the real SyncEngine through it.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/data/sync/remote_storage.dart';
import 'package:dgvault/platform/sync/webdav_remote_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A trivial in-memory WebDAV server for MockClient.
MockClient _server(Map<String, Uint8List> store, {List<String>? log}) {
  return MockClient((req) async {
    final path = req.url.path;
    log?.add('${req.method} $path');
    switch (req.method) {
      case 'HEAD':
        return http.Response('', store.containsKey(path) ? 200 : 404,
            headers: store.containsKey(path)
                ? {'content-length': '${store[path]!.length}', 'etag': 'v1'}
                : {},);
      case 'GET':
        final data = store[path];
        return data == null
            ? http.Response('', 404)
            : http.Response.bytes(data, 200);
      case 'PUT':
        store[path] = req.bodyBytes;
        return http.Response('', 201);
      default:
        return http.Response('', 405);
    }
  });
}

void main() {
  final base = Uri.parse('https://dav.example/remote.php/dav/files/me/');

  test('exists/upload/download/stat map to HEAD/PUT/GET', () async {
    final store = <String, Uint8List>{};
    final log = <String>[];
    final dav = WebDavRemoteStorage(
        baseUrl: base, username: 'me', password: 'pw', client: _server(store, log: log),);

    expect(await dav.exists('vault.kdbx'), isFalse);
    await dav.upload('vault.kdbx', Uint8List.fromList([1, 2, 3, 4]));
    expect(await dav.exists('vault.kdbx'), isTrue);
    expect(await dav.download('vault.kdbx'), [1, 2, 3, 4]);
    final meta = await dav.stat('vault.kdbx');
    expect(meta!.size, 4);
    expect(meta.etag, 'v1');

    expect(log.first, startsWith('HEAD '));
    expect(log.any((l) => l.startsWith('PUT ')), isTrue);
    expect(log.any((l) => l.startsWith('GET ')), isTrue);
  });

  test('Basic auth header is base64(user:pass)', () {
    expect(base64Auth('me', 'pw'), base64.encode(utf8.encode('me:pw')));
  });

  test('a non-2xx upload surfaces RemoteStorageException', () async {
    final dav = WebDavRemoteStorage(
        baseUrl: base,
        client: MockClient((_) async => http.Response('nope', 403)),);
    expect(() => dav.upload('x', Uint8List(1)),
        throwsA(isA<RemoteStorageException>()),);
  });

  test('download of a missing object is a RemoteStorageException', () async {
    final dav = WebDavRemoteStorage(baseUrl: base, client: _server({}));
    expect(() => dav.download('missing'), throwsA(isA<RemoteStorageException>()));
  });
}
