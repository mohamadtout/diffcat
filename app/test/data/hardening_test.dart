import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/etag_cache.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/github_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers 304 when the request carries [etag], else 200 with [body].
class _EtagServer implements HttpClientAdapter {
  _EtagServer(this.etag, this.body);

  final String etag;
  final Object body;
  final statuses = <int>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    final match = o.headers['If-None-Match'] == etag;
    statuses.add(match ? 304 : 200);
    return match
        ? ResponseBody.fromString('', 304)
        : ResponseBody.fromString(
            jsonEncode(body),
            200,
            headers: {
              'content-type': ['application/json'],
              'etag': [etag],
            },
          );
  }

  @override
  void close({bool force = false}) {}
}

class _Bytes implements HttpClientAdapter {
  _Bytes(this.size);
  final int size;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async =>
      ResponseBody(Stream.fromIterable([for (var i = 0; i < size; i += 1000) Uint8List(1000)]), 200);

  @override
  void close({bool force = false}) {}
}

GitHubClient _client(HttpClientAdapter adapter, {EtagCache? etags}) =>
    GitHubClient(dio: Dio(GitHubClient.baseOptions('t'))..httpClientAdapter = adapter, etags: etags);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('etags'));
  tearDown(() => dir.delete(recursive: true));

  test('ETags saved on disk make the next client (a new background run) ask conditionally', () async {
    final server = _EtagServer('"v1"', [
      {'name': 'main'},
    ]);
    final cache = FileEtagCache(dir);
    expect(await _client(server, etags: cache).getJson('/repos/o/r/branches'), [
      {'name': 'main'},
    ]);
    // A fresh client has an empty memory cache, as in the next background run.
    expect(await _client(server, etags: FileEtagCache(dir)).getJson('/repos/o/r/branches'), [
      {'name': 'main'},
    ]);
    expect(server.statuses, [200, 304]);

    await cache.clear();
    await _client(server, etags: FileEtagCache(dir)).getJson('/repos/o/r/branches');
    expect(server.statuses.last, 200, reason: 'cleared on sign-in/out');
  });

  test('pruning keeps the newest entries', () async {
    final cache = FileEtagCache(dir);
    for (var i = 0; i < FileEtagCache.maxEntries + 5; i++) {
      await cache.write('k$i', EtagEntry(etag: '$i', data: i));
    }
    await cache.prune();
    expect(dir.listSync(), hasLength(FileEtagCache.maxEntries));
    expect(await FileEtagCache(dir).read('nope'), isNull);
  });

  test('binary downloads stop at the size cap', () async {
    expect(await _client(_Bytes(5000)).getBytes('/x', maxBytes: 10000), hasLength(5000));
    await expectLater(_client(_Bytes(50000)).getBytes('/x', maxBytes: 10000), throwsA(isA<GitHubException>()));
  });

  test('secrets are re-saved once with the new keychain options, and kept', () async {
    FlutterSecureStorage.setMockInitialValues({StoreKeys.githubToken: 'tok', 'ssh.h.key': 'pem'});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SecureStore.migrate(appSecureStorage, prefs);
    expect(await appSecureStorage.readAll(), {StoreKeys.githubToken: 'tok', 'ssh.h.key': 'pem'});
    expect(prefs.getInt(StoreKeys.secureStorageVersion), 2);
  });
}
