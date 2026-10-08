import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/console/command_executor.dart';
import 'package:git_reviewer/features/console/console_models.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements GitHubApi {}

const _repo = (owner: 'acme', name: 'app');

GhCommit _commit(String sha, String msg) => GhCommit(
  sha: sha.padRight(40, '0'),
  message: msg,
  authorName: 'Ann',
  authorLogin: 'ann',
  date: DateTime(2026, 1, 1),
  parents: const [],
);

void main() {
  late _MockApi api;
  late CommandExecutor exec;

  setUpAll(() => registerFallbackValue(_repo));

  setUp(() {
    api = _MockApi();
    exec = CommandExecutor(api: api, repo: _repo, ref: 'main');
  });

  test('log lists commits with tappable routes', () async {
    when(() => api.commits(any(), ref: 'main', path: null, perPage: 3))
        .thenAnswer((_) async => GhPage([_commit('aaa', 'first'), _commit('bbb', 'second')], hasNext: false));
    final out = await exec.run('git log -n 3');
    expect(out, hasLength(2));
    expect(out.first.plain, contains('first'));
    expect(out.first.route, '/repos/acme/app/commit/${'aaa'.padRight(40, '0')}');
  });

  test('history passes the path through and focuses the file', () async {
    when(() => api.commits(any(), ref: 'main', path: 'lib/x.dart', perPage: 20))
        .thenAnswer((_) async => GhPage([_commit('ccc', 'touch x')], hasNext: true));
    final out = await exec.run('history lib/x.dart');
    expect(out.first.route, contains('file=lib%2Fx.dart'));
    expect(out.last.plain, contains('more'));
  });

  test('diff resolves HEAD~2 and renders name-status', () async {
    when(() => api.commits(any(), ref: 'main', perPage: 3))
        .thenAnswer((_) async => GhPage([_commit('c3', ''), _commit('c2', ''), _commit('c1', '')], hasNext: true));
    when(() => api.compare(any(), 'c1'.padRight(40, '0'), 'main')).thenAnswer(
      (_) async => const GhCompare(
        status: 'ahead',
        aheadBy: 2,
        behindBy: 0,
        totalCommits: 2,
        commits: [],
        files: [GhFileChange(filename: 'a.txt', status: FileChangeStatus.added, additions: 1, deletions: 0)],
      ),
    );
    final out = await exec.run('diff HEAD~2..HEAD');
    expect(out.first.plain, startsWith('c100000...main'));
    expect(out[1].plain, 'A  a.txt');
    expect(out.last.plain, contains('1 files changed'));
  });

  test('since @latest-tag uses the first tag', () async {
    when(() => api.tags(any())).thenAnswer((_) async => const [GhBranch(name: 'v2', sha: 'tagsha')]);
    when(() => api.compare(any(), 'tagsha', 'main')).thenAnswer(
      (_) async => const GhCompare(status: 'ahead', aheadBy: 0, behindBy: 0, totalCommits: 0, commits: [], files: []),
    );
    final out = await exec.run('since @latest-tag');
    expect(out.last.plain, '(no file changes)');
  });

  test('open resolves routes without network', () {
    expect(exec.routeFor('open #12'), '/repos/acme/app/pull/12');
    expect(exec.routeFor('open abcdef1'), '/repos/acme/app/commit/abcdef1');
    expect(exec.routeFor('open lib/a.dart'), '/repos/acme/app/file?path=lib%2Fa.dart&ref=main');
    expect(exec.routeFor('log'), isNull);
  });

  test('unknown command is a usage error', () {
    expect(() => exec.run('frobnicate'), throwsA(isA<ConsoleUsageError>()));
  });
}
