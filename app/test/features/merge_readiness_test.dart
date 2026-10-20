import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/pulls/merge_readiness.dart';

import '../support/demo_github.dart';

GhPull _pull({PullState state = PullState.open, String? mergeable = 'clean'}) => GhPull(
  number: 1,
  title: 't',
  body: '',
  state: state,
  author: const GhUser(login: 'a'),
  headRef: 'feature',
  headSha: 'abc',
  baseRef: 'main',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  mergeableState: mergeable,
);

GhCheckRun _check(String name, RunState state) => GhCheckRun(id: name.hashCode, name: name, state: state);

final _green = [_check('lint', RunState.success), _check('test', RunState.success), _check('x', RunState.skipped)];

void main() {
  test('checks are counted by outcome', () {
    final s = ChecksSummary.of([..._green, _check('build', RunState.failure), _check('e2e', RunState.inProgress)]);
    expect((s.passed, s.running, s.skipped), (2, 1, 1));
    expect(s.failed, ['build']);
    expect(s.label, '1 failing (build), 1 running, 2 passed, 1 skipped');
    expect(ChecksSummary.of(const []).label, 'No checks');
  });

  test('green checks, no conflicts and no changes requested: ready', () {
    final r = MergeReadiness.of(_pull(), checks: _green, reviewers: {'lena-k': ReviewState.approved});
    expect((r.verdict, r.headline), (Verdict.ready, 'Ready to merge'));
    expect(r.summary, 'Ready to merge · 2 passed, 1 skipped');
    expect(r.merge, 'No conflicts with main');
    expect(r.reviews, 'Approved by lena-k');
  });

  test('blockers win over waiting, in order: conflicts, failing checks, changes requested', () {
    final failing = [..._green, _check('build', RunState.failure)];
    final changes = {'marco': ReviewState.changesRequested};
    expect(
      MergeReadiness.of(
        _pull(mergeable: 'dirty'),
        checks: failing,
        reviewers: changes,
      ).headline,
      'Has conflicts',
    );
    expect(MergeReadiness.of(_pull(), checks: failing, reviewers: changes).headline, 'Checks failing');
    final r = MergeReadiness.of(_pull(), checks: _green, reviewers: changes);
    expect((r.verdict, r.headline, r.reviews), (Verdict.blocked, 'Changes requested', 'Changes requested by marco'));
  });

  test('waiting: draft, running checks, required reviews, still computing', () {
    expect(MergeReadiness.of(_pull(state: PullState.draft), checks: _green).headline, 'Draft');
    final running = [..._green, _check('e2e', RunState.queued)];
    expect(MergeReadiness.of(_pull(), checks: running).verdict, Verdict.waiting);
    expect(MergeReadiness.of(_pull(mergeable: 'blocked'), checks: _green).headline, 'Needs approval');
    expect(MergeReadiness.of(_pull(mergeable: 'unknown'), checks: _green).headline, 'Checking…');
    expect(MergeReadiness.of(_pull()).headline, 'Checking…', reason: 'checks still loading');
  });

  test("doesn't claim what it can't see: checks unavailable offline", () {
    final r = MergeReadiness.of(_pull(), checksUnavailable: true);
    expect((r.verdict, r.headline), (Verdict.waiting, 'Checks unavailable'));
  });

  test('merged and closed pull requests are done', () {
    expect(MergeReadiness.of(_pull(state: PullState.merged)).verdict, Verdict.done);
    expect(MergeReadiness.of(_pull(state: PullState.closed)).headline, 'Closed');
  });

  test('behind the base is noted, not blocking', () {
    final r = MergeReadiness.of(_pull(mergeable: 'behind'), checks: _green);
    expect((r.verdict, r.merge), (Verdict.ready, 'Behind main'));
  });

  test('check runs and the merge state are read from GitHub', () async {
    final api = GitHubApi(GitHubClient(dio: Dio(GitHubClient.baseOptions('t'))..httpClientAdapter = DemoGitHub()));
    final checks = await api.checkRuns(DemoGitHub.repo, DemoGitHub.sha(1));
    expect(checks.map((c) => c.state), [RunState.success, RunState.success, RunState.success, RunState.neutral]);
    final pull = await api.pull(DemoGitHub.repo, DemoGitHub.openPullNumber);
    expect(pull.mergeableState, 'clean');
  });
}
