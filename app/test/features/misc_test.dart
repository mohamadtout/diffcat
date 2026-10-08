import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/utils/relative_time.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/repos/repos_screen.dart';
import 'package:git_reviewer/features/settings/settings_screen.dart';

void main() {
  const repo = (owner: 'Acme', name: 'My.App');

  test('route builders encode query parameters', () {
    expect(Routes.commit(repo, 'abc', file: 'a b/c.dart'), '/repos/Acme/My.App/commit/abc?file=a+b%2Fc.dart');
    expect(Routes.repo(repo), '/repos/Acme/My.App');
    expect(Routes.compare(repo, 'v1', 'main'), '/repos/Acme/My.App/compare?base=v1&head=main');
  });

  test('relativeTime', () {
    final now = DateTime(2026, 10, 8, 12);
    expect(relativeTime(now.subtract(const Duration(seconds: 10)), now: now), 'just now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
    expect(relativeTime(now.subtract(const Duration(days: 2)), now: now), '2d ago');
    expect(relativeTime(DateTime(2025, 3, 1), now: now), 'Mar 1, 2025');
  });

  test('GhPull state derivation', () {
    Map<String, dynamic> pr({String state = 'open', bool draft = false, String? merged}) => {
      'number': 1,
      'title': 't',
      'state': state,
      'draft': draft,
      'merged_at': merged,
      'user': {'login': 'u'},
      'head': {'ref': 'f', 'sha': 's'},
      'base': {'ref': 'main'},
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };
    expect(GhPull.fromJson(pr()).state, PullState.open);
    expect(GhPull.fromJson(pr(draft: true)).state, PullState.draft);
    expect(GhPull.fromJson(pr(state: 'closed')).state, PullState.closed);
    expect(GhPull.fromJson(pr(state: 'closed', merged: '2026-01-02T00:00:00Z')).state, PullState.merged);
  });

  test('parseRepoInput accepts owner/name and GitHub URLs', () {
    expect(parseRepoInput('octo-org/my-app2'), (owner: 'octo-org', name: 'my-app2'));
    expect(parseRepoInput(' https://github.com/a-b/c.d.git/ '), (owner: 'a-b', name: 'c.d'));
    expect(parseRepoInput('just-a-name'), isNull);
    expect(parseRepoInput('a/b/c'), isNull);
  });

  test('notification settings copy never promises iOS background checks', () {
    expect(notificationCopy(TargetPlatform.iOS).schedule, isNot(contains('every')));
    expect(notificationCopy(TargetPlatform.iOS).help, isNot(contains('Android')));
    expect(notificationCopy(TargetPlatform.android).schedule, contains('every'));
  });
}
