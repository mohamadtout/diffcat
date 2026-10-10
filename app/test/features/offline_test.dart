import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/github_exception.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/data/github/response_cache.dart';
import 'package:git_reviewer/features/offline/downloader.dart';
import 'package:git_reviewer/features/offline/offline_store.dart';

/// Canned GitHub for one repo `o/r` with [commitCount] commits on main.
class _FakeGitHub implements HttpClientAdapter {
  int commitCount = 3;
  bool online = true;
  final requests = <String>[];

  static String sha(int i) => i.toRadixString(16).padLeft(40, '0');

  Map<String, dynamic> _commit(int i, {bool files = false}) => {
    'sha': sha(i),
    'commit': {
      'message': 'Commit $i',
      'author': {'name': 'Dev', 'date': '2026-10-0${1 + i % 8}T00:00:00Z'},
    },
    'parents': <Object>[],
    if (files)
      'files': [
        {'filename': 'f$i.txt', 'status': 'modified', 'additions': 1, 'deletions': 1, 'patch': '@@ -1 +1 @@\n-a\n+b$i'},
      ],
  };

  Map<String, dynamic> _pull(int n, {String state = 'open'}) => {
    'number': n,
    'title': 'PR $n',
    'state': state,
    'user': {'login': 'dev'},
    'head': {'ref': 'feature', 'sha': sha(90)},
    'base': {'ref': 'main', 'sha': sha(0)},
    'created_at': '2026-10-01T00:00:00Z',
    'updated_at': '2026-10-02T00:00:00Z',
  };

  Object? _route(RequestOptions o) {
    final p = o.path;
    final q = o.queryParameters;
    if (p == '/repos/o/r') {
      return {
        'name': 'r',
        'owner': {'login': 'o'},
        'default_branch': 'main',
      };
    }
    if (p == '/repos/o/r/branches' || p == '/repos/o/r/tags') {
      return [
        {
          'name': 'main',
          'commit': {'sha': sha(0)},
        },
      ];
    }
    if (p == '/repos/o/r/commits') {
      final page = q['page'] as int, per = q['per_page'] as int;
      final start = (page - 1) * per;
      return [for (var i = start; i < commitCount && i < start + per; i++) _commit(i)];
    }
    if (p.startsWith('/repos/o/r/commits/')) return _commit(int.parse(p.split('/').last, radix: 16), files: true);
    if (p.startsWith('/repos/o/r/git/trees/')) {
      return {
        'sha': sha(0),
        'tree': [
          {'path': 'README.md', 'type': 'blob', 'sha': 'x', 'size': 5},
        ],
      };
    }
    if (p == '/repos/o/r/pulls') {
      return switch (q['state']) {
        'closed' => [_pull(8, state: 'closed')],
        'all' => [_pull(7), _pull(8, state: 'closed')],
        _ => [_pull(7)],
      };
    }
    if (RegExp(r'^/repos/o/r/pulls/(7|8)$').hasMatch(p)) {
      final n = int.parse(p.split('/').last);
      return _pull(n, state: n == 8 ? 'closed' : 'open');
    }
    if (RegExp(r'^/repos/o/r/pulls/(7|8)/(files|reviews|comments)$').hasMatch(p)) return <Object>[];
    if (RegExp(r'^/repos/o/r/pulls/(7|8)/commits$').hasMatch(p)) return [_commit(0)];
    return null;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    if (!online) throw DioException.connectionError(requestOptions: o, reason: 'offline');
    requests.add(o.path);
    if (o.path == '/repos/o/r/tarball/main') {
      return ResponseBody.fromBytes(
        _tarball({'README.md': 'hello', 'bin.dat': '\u0000\u0001', 'src/a.dart': 'main(){}'}),
        200,
      );
    }
    final data = _route(o);
    if (data == null) {
      return ResponseBody.fromString(jsonEncode({'message': 'Not Found'}), 404, headers: _jsonHeaders);
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {..._jsonHeaders, 'link': ?_link(o)});
  }

  /// Pagination of the commit list, like GitHub's `Link` header.
  List<String>? _link(RequestOptions o) {
    if (o.path != '/repos/o/r/commits') return null;
    final page = o.queryParameters['page'] as int, per = o.queryParameters['per_page'] as int;
    final last = (commitCount / per).ceil();
    if (page >= last) return null;
    String url(int p) => '<https://api.github.com/repos/o/r/commits?per_page=$per&page=$p>';
    return ['${url(page + 1)}; rel="next", ${url(last)}; rel="last"'];
  }

  static const _jsonHeaders = {
    'content-type': ['application/json'],
  };

  @override
  void close({bool force = false}) {}
}

Uint8List _tarball(Map<String, String> files) {
  final archive = Archive();
  for (final f in files.entries) {
    final bytes = utf8.encode(f.value);
    archive.addFile(ArchiveFile('o-r-abc123/${f.key}', bytes.length, bytes));
  }
  return Uint8List.fromList(const GZipEncoder().encode(TarEncoder().encode(archive)));
}

GitHubApi _api(
  _FakeGitHub fake, {
  ResponseCache? cache,
  CacheMode mode = CacheMode.replay,
  bool Function(String key)? preferSaved,
}) => GitHubApi(
  GitHubClient(
    dio: Dio(BaseOptions(baseUrl: 'https://api.github.com'))..httpClientAdapter = fake,
    cache: cache,
    cacheMode: mode,
    preferSaved: preferSaved,
  ),
);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('offline_test'));
  tearDown(() => dir.delete(recursive: true));

  test('requests are filed under the repo part they belong to', () {
    expect(classifyRequest('/repos/o/r', null), (repo: 'o/r', group: Groups.repo));
    expect(classifyRequest('/repos/o/r/branches', {'page': 1})?.group, Groups.repo);
    expect(classifyRequest('/repos/o/r/commits', {'sha': 'dev', 'page': 2})?.group, Groups.branch('dev'));
    expect(classifyRequest('/repos/o/r/commits', {'sha': 'dev', 'path': 'a.txt'})?.group, Groups.other);
    expect(classifyRequest('/repos/o/r/commits/${'AB' * 20}', null)?.group, Groups.commit('ab' * 20));
    expect(classifyRequest('/repos/o/r/git/trees/feature%2Fx', {'recursive': '1'})?.group, Groups.branch('feature/x'));
    expect(classifyRequest('/repos/o/r/contents/a/b.txt', {'ref': 'main'})?.group, Groups.files('main'));
    expect(classifyRequest('/repos/o/r/pulls/12/files', {'page': 1})?.group, Groups.pull(12));
    expect(classifyRequest('/user/repos', null), isNull);
  });

  test('download saves a branch, and the UI client reads it back with no network', () async {
    final store = await OfflineStore.open(dir);
    final fake = _FakeGitHub();
    final progress = <DownloadProgress>[];
    await BranchDownloader(
      store: store,
      repo: (owner: 'o', name: 'r'),
      branch: 'main',
      options: const DownloadOptions(),
      onProgress: progress.add,
      api: _api(fake, cache: store, mode: CacheMode.record),
    ).run();
    expect(progress.last.finished, isTrue);
    expect(progress.last.error, isNull);

    fake.online = false;
    final ui = _api(fake, cache: store);
    const repo = (owner: 'O', name: 'R'); // GitHub names are case-insensitive
    expect((await ui.repo(repo)).defaultBranch, 'main');
    final page = await ui.commits(repo, ref: 'main', perPage: 30);
    expect(page.items.map((c) => c.title), ['Commit 0', 'Commit 1', 'Commit 2']);
    expect((await ui.commit(repo, _FakeGitHub.sha(1))).files.single.patch, contains('+b1'));
    expect((await ui.tree(repo, 'main')).entries.single.path, 'README.md');
    expect((await ui.pullFiles(repo, 7)), isEmpty);
    await expectLater(ui.fileContent(repo, 'README.md', 'main'), throwsA(anything), reason: 'files not downloaded');

    final saved = store.repo('o/r')!;
    expect(saved.branches['main']!.commits.map((c) => c.title), ['Commit 0', 'Commit 1', 'Commit 2']);
    expect(saved.pulls, {7: 'PR 7'});
    expect(saved.branchBytes('main'), greaterThan(0));
    expect(saved.bytes, greaterThan(saved.branchBytes('main')));
  });

  test('update fetches only new commit diffs; full files come from one archive', () async {
    final store = await OfflineStore.open(dir);
    final fake = _FakeGitHub();
    Future<void> download(DownloadOptions options) => BranchDownloader(
      store: store,
      repo: (owner: 'o', name: 'r'),
      branch: 'main',
      options: options,
      onProgress: (_) {},
      api: _api(fake, cache: store, mode: CacheMode.record),
    ).run();

    await download(const DownloadOptions(pulls: PullScope.none));
    fake
      ..commitCount = 4
      ..requests.clear();
    await download(const DownloadOptions(pulls: PullScope.none, files: true));
    final commitDetails = fake.requests.where((p) => p.startsWith('/repos/o/r/commits/')).toList();
    expect(commitDetails, ['/repos/o/r/commits/${_FakeGitHub.sha(3)}'], reason: 'only the new commit');
    expect(fake.requests.where((p) => p.contains('/tarball/')), hasLength(1));

    fake.online = false;
    final ui = _api(fake, cache: store);
    expect(await ui.fileContent((owner: 'o', name: 'r'), 'src/a.dart', 'main'), 'main(){}');
    await expectLater(ui.fileContent((owner: 'o', name: 'r'), 'bin.dat', 'main'), throwsA(anything));
    expect(store.repo('o/r')!.groupBytes(Groups.files('main')), greaterThan(0));
  });

  test('selective deletes keep what other branches still use, and survive a restart', () async {
    var store = await OfflineStore.open(dir);
    Future<void> put(String path, Map<String, dynamic>? query, Object data) =>
        store.write(GitHubClient.cacheKey(path, query: query), path, query, CachedResponse(data: data));
    final shared = 'a' * 40, onlyMain = 'b' * 40, onlyDev = 'c' * 40;
    await put('/repos/o/r', null, {'name': 'r'});
    for (final sha in [shared, onlyMain, onlyDev]) {
      await put('/repos/o/r/commits/$sha', null, {'sha': sha});
    }
    await put('/repos/o/r/commits', {'sha': 'main', 'page': 1}, <Object>[]);
    await put('/repos/o/r/contents/a.txt', {'ref': 'main'}, 'text');
    await put('/repos/o/r/pulls/3', null, {'number': 3});
    final now = DateTime(2026, 10, 8);
    store
      ..saveBranch(
        'o/r',
        'main',
        SavedBranch(
          updatedAt: now,
          options: const DownloadOptions(),
          commits: [SavedCommit(shared, 's'), SavedCommit(onlyMain, 'm')],
        ),
        pulls: {3: 'PR'},
      )
      ..saveBranch(
        'o/r',
        'dev',
        SavedBranch(
          updatedAt: now,
          options: const DownloadOptions(),
          commits: [SavedCommit(shared, 's'), SavedCommit(onlyDev, 'd')],
        ),
      );
    await store.flush();

    store = await OfflineStore.open(dir); // restart
    expect(store.repo('O/R')!.branches.keys, unorderedEquals(['main', 'dev']));
    expect(store.hasCommit('o/r', onlyMain), isTrue);

    await store.deleteBranchFiles('o/r', 'main');
    expect(store.repo('o/r')!.hasGroup(Groups.files('main')), isFalse);

    await store.deleteBranch('o/r', 'main');
    expect(store.hasCommit('o/r', onlyMain), isFalse);
    expect(store.hasCommit('o/r', shared), isTrue, reason: 'dev still has it');
    expect(store.repo('o/r')!.hasGroup(Groups.branch('main')), isFalse);

    await store.deleteCommit('o/r', onlyDev);
    expect(store.hasCommit('o/r', onlyDev), isFalse);
    await store.deletePull('o/r', 3);
    expect(store.repo('o/r')!.pulls, isEmpty);

    await store.deleteBranch('o/r', 'dev');
    expect(store.repo('o/r'), isNull, reason: 'nothing meaningful left');
    expect(await Directory('${dir.path}/o__r').exists(), isFalse);
  });

  test('a missing saved file falls back to the network instead of failing', () async {
    final store = await OfflineStore.open(dir);
    final key = GitHubClient.cacheKey('/repos/o/r');
    await store.write(key, '/repos/o/r', null, const CachedResponse(data: {'name': 'r'}));
    await store.flush();
    for (final f in Directory('${dir.path}/o__r').listSync().whereType<File>()) {
      if (!f.path.endsWith('index.json')) f.deleteSync();
    }
    expect(await store.read(key), isNull);
  });

  test('extractTextFiles strips the archive folder and skips binary and huge files', () {
    final files = extractTextFiles(_tarball({'a.txt': 'hi', 'b.bin': 'x\u0000y', 'c.txt': 'x' * 50}), maxBytes: 20);
    expect(files, {'a.txt': 'hi'});
  });

  test('formatBytes', () {
    expect(formatBytes(999), '999 B');
    expect(formatBytes(12300), '12 KB');
    expect(formatBytes(4500000), '4.5 MB');
  });

  test('offline mode serves only saved data and never touches the network', () async {
    final store = await OfflineStore.open(dir);
    final fake = _FakeGitHub();
    await BranchDownloader(
      store: store,
      repo: (owner: 'o', name: 'r'),
      branch: 'main',
      options: const DownloadOptions(pulls: PullScope.none),
      onProgress: (_) {},
      api: _api(fake, cache: store, mode: CacheMode.record),
    ).run();
    fake.requests.clear();

    final ui = GitHubApi(
      GitHubClient(
        dio: Dio(BaseOptions(baseUrl: 'https://api.github.com'))..httpClientAdapter = fake,
        cache: store,
        cacheOnly: (key) => OfflineStore.repoOfKey(key) == 'o/r',
      ),
    );
    expect((await ui.commits((owner: 'o', name: 'r'), ref: 'main', perPage: 30)).items, hasLength(3));
    await expectLater(
      ui.pulls((owner: 'o', name: 'r')),
      throwsA(isA<GitHubException>().having((e) => e.notDownloaded, 'notDownloaded', isTrue)),
    );
    expect(GitHubException.notDownloaded().isRetryable, isFalse);
    expect(fake.requests, isEmpty, reason: 'nothing went to the network');

    await expectLater(ui.repo((owner: 'other', name: 'x')), throwsA(isA<GitHubException>()));
    expect(fake.requests, ['/repos/other/x'], reason: 'other repos still use the network');
  });

  test('only requests pinned to a commit count as unchanging', () {
    final sha = 'a' * 40;
    String key(String path, [Map<String, dynamic>? q, String? accept]) =>
        GitHubClient.cacheKey(path, query: q, accept: accept);
    expect(isImmutableKey(key('/repos/o/r/commits/$sha')), isTrue);
    expect(isImmutableKey(key('/repos/o/r/commits/abc1234')), isTrue, reason: 'a short sha names one commit too');
    expect(isImmutableKey(key('/repos/o/r/commits/$sha', {'page': 2, 'per_page': 100})), isTrue);
    expect(isImmutableKey(key('/repos/o/r/git/trees/$sha', {'recursive': '1'})), isTrue);
    expect(isImmutableKey(key('/repos/o/r/contents/a/b.txt', {'ref': sha}, GitHubClient.rawAccept)), isTrue);
    expect(isImmutableKey(key('/repos/o/r/compare/$sha...${'b' * 40}')), isTrue);

    expect(isImmutableKey(key('/repos/o/r/commits', {'sha': sha})), isFalse, reason: 'history grows');
    expect(isImmutableKey(key('/repos/o/r/commits/main')), isFalse, reason: 'a branch moves');
    expect(isImmutableKey(key('/repos/o/r/git/trees/main', {'recursive': '1'})), isFalse);
    expect(isImmutableKey(key('/repos/o/r/contents/a.txt', {'ref': 'main'}, GitHubClient.rawAccept)), isFalse);
    expect(isImmutableKey(key('/repos/o/r/compare/main...$sha')), isFalse);
    expect(isImmutableKey(key('/repos/o/r/pulls/7')), isFalse);
    expect(isImmutableKey(key('/repos/o/r')), isFalse);
  });

  group('online with a download', () {
    late OfflineStore store;
    late _FakeGitHub fake;
    const repo = (owner: 'o', name: 'r');

    setUp(() async {
      store = await OfflineStore.open(dir);
      fake = _FakeGitHub();
      await BranchDownloader(
        store: store,
        repo: repo,
        branch: 'main',
        options: const DownloadOptions(),
        onProgress: (_) {},
        api: _api(fake, cache: store, mode: CacheMode.record),
      ).run();
      fake
        ..requests.clear()
        ..commitCount = 4; // a new commit was pushed since the download
    });

    test('fresh: lists load live, a downloaded diff costs no request', () async {
      final ui = _api(fake, cache: store, preferSaved: isImmutableKey);
      expect((await ui.commits(repo, ref: 'main', perPage: 30)).items, hasLength(4), reason: 'live');
      expect((await ui.commit(repo, _FakeGitHub.sha(1))).files.single.patch, contains('+b1'));
      expect(fake.requests, ['/repos/o/r/commits'], reason: 'the saved diff was used');

      await ui.commit(repo, _FakeGitHub.sha(3));
      expect(fake.requests.last, '/repos/o/r/commits/${_FakeGitHub.sha(3)}', reason: 'not downloaded: network');
    });

    test('fresh: the download stands in when GitHub is unreachable', () async {
      fake.online = false;
      final ui = _api(fake, cache: store, preferSaved: isImmutableKey);
      expect((await ui.commits(repo, ref: 'main', perPage: 30)).items, hasLength(3), reason: 'as downloaded');
      expect(await ui.pulls(repo).then((p) => p.items.single.number), 7);
      await expectLater(ui.repo((owner: 'other', name: 'x')), throwsA(isA<GitHubException>()));
    });

    test('data saver: everything downloaded loads from the device', () async {
      final ui = _api(fake, cache: store); // preferSaved null: saved first
      expect((await ui.commits(repo, ref: 'main', perPage: 30)).items, hasLength(3), reason: 'as downloaded');
      await ui.pulls(repo);
      await ui.commit(repo, _FakeGitHub.sha(1));
      expect(fake.requests, isEmpty);
    });
  });

  group('download options', () {
    late OfflineStore store;
    late _FakeGitHub fake;
    const repo = (owner: 'o', name: 'r');
    setUp(() async {
      store = await OfflineStore.open(dir);
      fake = _FakeGitHub()..commitCount = 100;
    });
    Future<List<String>> download(DownloadOptions options) async {
      await BranchDownloader(
        store: store,
        repo: repo,
        branch: 'main',
        options: options,
        onProgress: (_) {},
        api: _api(fake, cache: store, mode: CacheMode.record),
      ).run();
      return [for (final c in store.repo('o/r')!.branches['main']!.commits) c.sha];
    }

    test('any number of the latest commits', () async {
      final shas = await download(const DownloadOptions(commits: 45, pulls: PullScope.none));
      expect(shas, [for (var i = 0; i < 45; i++) _FakeGitHub.sha(i)]);
      expect(fake.requests.where((p) => p == '/repos/o/r/commits'), hasLength(2), reason: '2 pages of 30');
    });

    test('since a commit: it and everything newer', () async {
      final since = _FakeGitHub.sha(40).toUpperCase(); // fake shas share prefixes, so the full one
      final shas = await download(DownloadOptions(range: CommitRange.since, since: since, pulls: PullScope.none));
      expect(shas, hasLength(41));
      expect(shas.last, _FakeGitHub.sha(40));
      expect(fake.requests.where((p) => p == '/repos/o/r/commits'), hasLength(2), reason: 'stops paging once found');

      await expectLater(
        download(const DownloadOptions(range: CommitRange.since, since: 'deadbeef', pulls: PullScope.none)),
        throwsA(isA<SinceCommitNotFound>().having((e) => '$e', 'message', contains('last 100 commits of main'))),
      );
    });

    test('the whole history, counted in one request', () async {
      final shas = await download(const DownloadOptions(range: CommitRange.all, pulls: PullScope.none));
      expect(shas, hasLength(100));
      fake.requests.clear();
      expect(await _api(fake).commitCount(repo, 'main'), 100);
      expect(fake.requests, hasLength(1));
      fake.commitCount = 1;
      expect(await _api(fake).commitCount(repo, 'main'), 1, reason: 'no Link header with a single page');
    });

    test('open and closed pull requests, with their review threads, read offline', () async {
      fake.commitCount = 3;
      await download(const DownloadOptions(pulls: PullScope.openAndClosed));
      final saved = store.repo('o/r')!;
      expect(saved.pulls, {7: 'PR 7', 8: 'PR 8'});
      expect(saved.groupBytes(Groups.pull(8)), greaterThan(0));
      final reviews = GitHubClient.cacheKey('/repos/o/r/pulls/8/reviews', query: {'per_page': 100, 'page': 1});
      expect(saved.entries[reviews]?.group, Groups.pull(8), reason: 'review threads belong to the PR');

      fake.online = false;
      final ui = GitHubApi(
        GitHubClient(
          dio: Dio(BaseOptions(baseUrl: 'https://api.github.com'))..httpClientAdapter = fake,
          cache: store,
          cacheOnly: (key) => true,
        ),
      );
      expect((await ui.pulls(repo, state: 'closed')).items.single.number, 8);
      expect((await ui.pulls(repo, state: 'all')).items, hasLength(2));
      expect(await ui.reviews(repo, 8), isEmpty);
      expect(await ui.reviewComments(repo, 7), isEmpty);
    });

    test('one pull request on its own, from its screen', () async {
      await PullDownloader(
        store: store,
        repo: repo,
        number: 8,
        onProgress: (_) {},
        api: _api(fake, cache: store, mode: CacheMode.record),
      ).run();
      final saved = (await OfflineStore.open(dir)).repo('o/r')!;
      expect(saved.pulls, {8: 'PR 8'});
      expect(saved.branches, isEmpty);
      expect(fake.requests, [
        '/repos/o/r',
        '/repos/o/r/pulls/8',
        '/repos/o/r/pulls/8/files',
        '/repos/o/r/pulls/8/commits',
        '/repos/o/r/pulls/8/reviews',
        '/repos/o/r/pulls/8/comments',
      ]);
    });

    test('options survive JSON, and old ones still read', () {
      const o = DownloadOptions(
        range: CommitRange.since,
        since: 'abc1234',
        pulls: PullScope.openAndClosed,
        files: true,
      );
      final back = DownloadOptions.fromJson(o.toJson());
      expect(
        (back.range, back.since, back.pulls, back.files),
        (CommitRange.since, 'abc1234', PullScope.openAndClosed, true),
      );
      expect(back.rangeLabel, 'since abc1234');

      final old = DownloadOptions.fromJson({'commits': 100, 'pulls': false, 'files': false});
      expect((old.range, old.commits, old.pulls), (CommitRange.recent, 100, PullScope.none));
      expect(DownloadOptions.fromJson({'commits': 30, 'pulls': true}).pulls, PullScope.open);
      expect(const DownloadOptions(range: CommitRange.all).rangeLabel, 'full history');
    });

    test('"All files" estimate skips big and binary files', () {
      GhTreeEntry blob(String path, int size) =>
          GhTreeEntry(path: path, type: TreeEntryType.blob, sha: 'x', size: size);
      final e = estimateTextFiles(
        GhTree(
          sha: 'x',
          truncated: true,
          entries: [
            blob('README.md', 1000),
            blob('src/a.dart', 3000),
            blob('assets/logo.PNG', 50000),
            blob('data/huge.json', 5000000),
            const GhTreeEntry(path: 'src', type: TreeEntryType.tree, sha: 'y'),
          ],
        ),
      );
      expect((e.files, e.truncated), (2, true));
      expect(e.bytes, greaterThanOrEqualTo(4000));
      expect(e.bytes, lessThan(4500));
    });
  });
}
