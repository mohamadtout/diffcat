import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/github_exception.dart';

/// Scripted HTTP adapter: returns queued responses and records requests.
class _FakeAdapter implements HttpClientAdapter {
  final responses = <ResponseBody Function(RequestOptions)>[];
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(options);
    return responses.removeAt(0)(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200, Map<String, String> headers = const {}}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
    for (final e in headers.entries) e.key: [e.value],
  },
);

void main() {
  late _FakeAdapter adapter;
  late GitHubClient client;

  setUp(() {
    adapter = _FakeAdapter();
    final dio = Dio(
      BaseOptions(baseUrl: 'https://api.github.com', validateStatus: (s) => s != null && (s < 300 || s == 304)),
    )..httpClientAdapter = adapter;
    client = GitHubClient(token: 't', dio: dio);
  });

  test('replays cached body on 304 and sends If-None-Match', () async {
    adapter.responses
      ..add((_) => _json({'login': 'me'}, headers: {'etag': '"abc"'}))
      ..add((_) => ResponseBody.fromString('', 304));
    expect(await client.getJson('/user'), {'login': 'me'});
    expect(await client.getJson('/user'), {'login': 'me'});
    expect(adapter.requests.last.headers['If-None-Match'], '"abc"');
  });

  test('getAll follows Link rel=next', () async {
    adapter.responses
      ..add(
        (_) => _json(
          [
            {'n': 1},
          ],
          headers: {'link': '<https://x?page=2>; rel="next"'},
        ),
      )
      ..add(
        (_) => _json([
          {'n': 2},
        ]),
      );
    final all = await client.getAll('/items', parse: (j) => j['n'] as int);
    expect(all, [1, 2]);
    expect(adapter.requests.last.queryParameters['page'], 2);
  });

  test('maps rate limiting to GitHubException.isRateLimited', () async {
    adapter.responses.add(
      (_) => _json(
        {'message': 'API rate limit exceeded'},
        status: 403,
        headers: {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1900000000'},
      ),
    );
    await expectLater(
      client.getJson('/user'),
      throwsA(isA<GitHubException>().having((e) => e.isRateLimited, 'rate limited', isTrue)),
    );
  });

  test('maps 404 with GitHub message', () async {
    adapter.responses.add((_) => _json({'message': 'Not Found'}, status: 404));
    await expectLater(
      client.getJson('/repos/x/y'),
      throwsA(
        isA<GitHubException>()
            .having((e) => e.isNotFound, 'not found', isTrue)
            .having((e) => e.isRetryable, 'retryable', isFalse),
      ),
    );
  });

  test('signed out sends no Authorization header; signed in sends the token', () {
    expect(GitHubClient.baseOptions(null).headers.containsKey('Authorization'), isFalse);
    expect(GitHubClient.baseOptions('t').headers['Authorization'], 'Bearer t');
  });

  test('anonymous rate limit explains the 60/hour limit and how to raise it', () async {
    final anon = Dio(GitHubClient.baseOptions(null))..httpClientAdapter = adapter;
    adapter.responses.add(
      (_) => _json(
        {'message': 'API rate limit exceeded'},
        status: 403,
        headers: {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1900000000'},
      ),
    );
    final error = await GitHubClient(dio: anon)
        .getJson('/repos/a/b')
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<GitHubException>().having((e) => e.isRateLimited, 'isRateLimited', isTrue));
    expect(error.toString(), allOf(contains('60 requests'), contains('Sign in')));
  });
}
