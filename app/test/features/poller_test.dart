import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/github_exception.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/notifications/poll_state.dart';
import 'package:git_reviewer/features/notifications/poller.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApi extends Mock implements GitHubApi {}

const _repo = (owner: 'acme', name: 'app');

String _sha(String s) => s.padRight(40, '0');

GhCommit _commit(String sha, String title, {String login = 'bob'}) => GhCommit(
  sha: _sha(sha),
  message: title,
  authorName: login,
  authorLogin: login,
  date: DateTime(2026, 10, 1),
  parents: const [],
);

GhPull _pull(
  int n, {
  String state = 'open',
  bool draft = false,
  String? mergedAt,
  String login = 'bob',
  String created = '2026-10-08T10:00:00Z',
}) => GhPull.fromJson({
  'number': n,
  'title': 'PR $n',
  'state': state,
  'draft': draft,
  'merged_at': mergedAt,
  'user': {'login': login},
  'head': {'ref': 'f', 'sha': 'x'},
  'base': {'ref': 'main'},
  'created_at': created,
  'updated_at': created,
});

GhCompare _cmp(String status, List<GhCommit> commits) => GhCompare(
  status: status,
  aheadBy: commits.length,
  behindBy: 0,
  totalCommits: commits.length,
  commits: commits,
  files: const [],
);

void main() {
  group('pure helpers', () {
    test('diffBranches reports new and moved branches only', () {
      final moves = diffBranches(
        {'main': 'a', 'old': 'x', 'same': 's'},
        const [GhBranch(name: 'main', sha: 'b'), GhBranch(name: 'same', sha: 's'), GhBranch(name: 'feat', sha: 'f')],
      );
      expect(moves, [(branch: 'main', from: 'a', to: 'b'), (branch: 'feat', from: null, to: 'f')]);
    });

    test('pullEvents: opened, ready, reopened, merged; skips drafts, closes, self, bots', () {
      final since = DateTime.parse('2026-10-08T09:00:00Z');
      final before = {
        2: const PullSnapshot(state: PullState.open, draft: true),
        3: const PullSnapshot(state: PullState.closed, draft: false),
        4: const PullSnapshot(state: PullState.open, draft: false),
        5: const PullSnapshot(state: PullState.open, draft: false),
        8: const PullSnapshot(state: PullState.open, draft: false),
      };
      final now = [
        _pull(1), // new, open → opened
        _pull(2), // draft → ready
        _pull(3), // closed → reopened
        _pull(4, state: 'closed', mergedAt: '2026-10-08T11:00:00Z'), // merged
        _pull(5, state: 'closed'), // closed: silent
        _pull(6, draft: true), // new draft: silent
        _pull(7, login: 'me'), // own PR: silent
        _pull(8, state: 'closed', mergedAt: '2026-10-08T11:00:00Z', login: 'me'), // own merge: notifies
        _pull(9, login: 'dependabot[bot]'), // bot: silent
        _pull(10, created: '2026-10-01T00:00:00Z'), // unknown but old: silent
      ];
      final titles = pullEvents(_repo, before, now, since: since, selfLogin: 'ME').map((e) => e.title);
      expect(titles, [
        'app · PR #1 opened',
        'app · PR #2 ready for review',
        'app · PR #3 reopened',
        'app · PR #4 merged',
        'app · PR #8 merged',
      ]);
    });

    test('pushEvent routes: one commit → commit, many → compare, force → head', () {
      final one = pushEvent(_repo, branch: 'main', from: _sha('a'), to: _sha('b'), commits: [_commit('b', 'Fix')])!;
      expect(one.route, '/repos/acme/app/commit/${_sha('b')}');
      expect(one.body, 'bob: Fix');

      final many = pushEvent(
        _repo,
        branch: 'main',
        from: _sha('a'),
        to: _sha('e'),
        commits: [for (final c in 'bcde'.split('')) _commit(c, 'c$c')],
      )!;
      expect(many.title, 'app · main: 4 new commits');
      expect(many.body, '• ce\n• cd\n• cc\n+1 more');
      expect(many.route, '/repos/acme/app/compare?base=${_sha('a')}&head=${_sha('e')}');

      final forced = pushEvent(
        _repo,
        branch: 'main',
        from: _sha('a'),
        to: _sha('c'),
        commits: [_commit('c', 'x')],
        forced: true,
      )!;
      expect(forced.title, contains('force-pushed'));
      expect(forced.route, '/repos/acme/app/commit/${_sha('c')}');

      expect(pushEvent(_repo, branch: 'main', from: 'a', to: 'b', commits: const []), isNull);
    });

    test('state round-trips through JSON', () {
      final s = RepoPollState(
        branches: {'main': 'a'},
        pulls: {3: const PullSnapshot(state: PullState.merged, draft: false)},
        checkedAt: DateTime.utc(2026, 10, 8),
      );
      final back = RepoPollState.fromJson(s.toJson());
      expect(back.branches, {'main': 'a'});
      expect(back.pulls[3]!.state, PullState.merged);
      expect(back.checkedAt, DateTime.utc(2026, 10, 8));
    });
  });

  group('Poller', () {
    late _MockApi api;
    late SharedPreferences prefs;
    var clock = DateTime.parse('2026-10-08T09:00:00Z');

    setUpAll(() => registerFallbackValue(_repo));

    setUp(() async {
      api = _MockApi();
      SharedPreferences.setMockInitialValues({
        StoreKeys.watchedRepos: ['acme/app', 'acme/gone'],
        StoreKeys.viewerLogin: 'me',
      });
      prefs = await SharedPreferences.getInstance();
      clock = DateTime.parse('2026-10-08T09:00:00Z');
      when(() => api.repo(any())).thenThrow(UnimplementedError());
      when(() => api.pulls(any(), state: 'all')).thenAnswer((_) async => const GhPage<GhPull>([], hasNext: false));
    });

    Poller poller() => Poller(api: api, prefs: prefs, clock: () => clock);

    test('first check is a silent baseline; next check reports new commits', () async {
      when(() => api.branches(_repo)).thenAnswer((_) async => [GhBranch(name: 'main', sha: _sha('a'))]);
      when(() => api.branches((owner: 'acme', name: 'gone'))).thenThrow(GitHubException('Not Found', statusCode: 404));

      final first = await poller().run();
      expect(first.events, isEmpty);
      expect(first.errors.keys, ['acme/gone']);

      clock = clock.add(const Duration(minutes: 15));
      when(() => api.branches(_repo)).thenAnswer((_) async => [GhBranch(name: 'main', sha: _sha('c'))]);
      when(() => api.compare(_repo, _sha('a'), _sha('c')))
          .thenAnswer((_) async => _cmp('ahead', [_commit('b', 'mine', login: 'me'), _commit('c', 'theirs')]));
      final second = await poller().run();
      // Own commit filtered out, so a single-commit event for bob's commit.
      expect(second.events.single.title, 'app · main');
      expect(second.events.single.body, 'bob: theirs');

      // Nothing changed → nothing new.
      clock = clock.add(const Duration(minutes: 15));
      expect((await poller().run()).events, isEmpty);
    });

    test('branch reset backwards does not notify; own-only pushes do not notify', () async {
      when(() => api.branches(_repo)).thenAnswer((_) async => [GhBranch(name: 'main', sha: _sha('a'))]);
      when(() => api.branches((owner: 'acme', name: 'gone'))).thenAnswer((_) async => []);
      await poller().run();

      when(() => api.branches(_repo)).thenAnswer((_) async => [GhBranch(name: 'main', sha: _sha('z'))]);
      when(() => api.compare(_repo, _sha('a'), _sha('z'))).thenAnswer((_) async => _cmp('behind', const []));
      expect((await poller().run()).events, isEmpty);

      when(() => api.branches(_repo)).thenAnswer((_) async => [GhBranch(name: 'main', sha: _sha('y'))]);
      when(() => api.compare(_repo, _sha('z'), _sha('y')))
          .thenAnswer((_) async => _cmp('ahead', [_commit('y', 'mine', login: 'me')]));
      expect((await poller().run()).events, isEmpty);
    });

    test('include-own setting notifies about your own commits', () async {
      await prefs.setBool(StoreKeys.notifyIncludeOwn, true);
      when(() => api.branches(any())).thenAnswer((_) async => [GhBranch(name: 'main', sha: _sha('a'))]);
      await poller().run();
      when(() => api.branches(any())).thenAnswer((_) async => [GhBranch(name: 'main', sha: _sha('b'))]);
      when(() => api.compare(any(), _sha('a'), _sha('b')))
          .thenAnswer((_) async => _cmp('ahead', [_commit('b', 'mine', login: 'me')]));
      expect((await poller().run()).events, hasLength(2)); // both watched repos moved
    });
  });
}
