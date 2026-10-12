import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/utils/relative_time.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/actions/job_log.dart';
import 'package:git_reviewer/features/actions/workflow_dispatch.dart';

import '../support/demo_github.dart';

void main() {
  group('RunState', () {
    test('combines status and conclusion', () {
      expect(RunState.from('queued', null), RunState.queued);
      expect(RunState.from('requested', null), RunState.queued);
      expect(RunState.from('in_progress', null), RunState.inProgress);
      expect(RunState.from('waiting', null), RunState.waiting);
      expect(RunState.from('completed', 'success'), RunState.success);
      expect(RunState.from('completed', 'timed_out'), RunState.failure);
      expect(RunState.from('completed', 'startup_failure'), RunState.failure);
      expect(RunState.from('completed', 'cancelled'), RunState.cancelled);
      expect(RunState.from('completed', 'stale'), RunState.neutral);
      expect(RunState.inProgress.isActive, isTrue);
      expect(RunState.failure.isActive, isFalse);
    });
  });

  test('a run takes its title from display_title and lasts from start to last update', () {
    final run = GhWorkflowRun.fromJson({
      'id': 1,
      'name': 'CI',
      'display_title': 'Fix rounding',
      'workflow_id': 9,
      'run_number': 12,
      'event': 'push',
      'status': 'completed',
      'conclusion': 'failure',
      'head_sha': 'abc',
      'created_at': '2026-10-12T10:00:00Z',
      'run_started_at': '2026-10-12T10:00:30Z',
      'updated_at': '2026-10-12T10:03:42Z',
    });
    expect(run.title, 'Fix rounding');
    expect(run.workflowName, 'CI');
    expect(run.state, RunState.failure);
    expect(run.duration(), const Duration(minutes: 3, seconds: 12));
    expect(shortDuration(run.duration()), '3m 12s');
    expect(shortDuration(const Duration(seconds: 45)), '45s');
    expect(shortDuration(const Duration(hours: 1, minutes: 5, seconds: 9)), '1h 5m');
  });

  test('runs page on total_count (the endpoint answers an object, not a list)', () async {
    final api = GitHubApi(GitHubClient(dio: Dio(GitHubClient.baseOptions('t'))..httpClientAdapter = DemoGitHub()));
    final all = await api.workflowRuns(DemoGitHub.repo, perPage: 4);
    expect(all.items, hasLength(4));
    expect(all.hasNext, isTrue);
    final deploys = await api.workflowRuns(DemoGitHub.repo, workflowId: DemoGitHub.deployWorkflowId);
    expect(deploys.items.single.workflowName, 'Deploy');
    expect(deploys.hasNext, isFalse);
  });

  group('parseWorkflowDispatch', () {
    test('no manual trigger', () {
      expect(parseWorkflowDispatch('on: push\njobs: {}'), isNull);
      expect(parseWorkflowDispatch('on: [push, pull_request]\njobs: {}'), isNull);
      expect(parseWorkflowDispatch('on:\n  push:\n    branches: [main]\n'), isNull);
    });

    test('a manual trigger without inputs, in each spelling', () {
      for (final src in [
        'on: workflow_dispatch',
        'on: [push, workflow_dispatch]',
        'on:\n  push:\n  workflow_dispatch:\n',
        '"on":\n  workflow_dispatch: {}\n',
        'true:\n  workflow_dispatch:\n', // how a YAML 1.1 parser reads a bare `on`
      ]) {
        expect(parseWorkflowDispatch(src)?.inputs, isEmpty, reason: src);
      }
    });

    test('reads every input type with its defaults', () {
      final d = parseWorkflowDispatch('''
on:
  workflow_dispatch:
    inputs:
      environment:
        description: Where to deploy
        type: choice
        options: [staging, production]
        required: true
      dry_run:
        type: boolean
        default: true
      replicas:
        type: number
        default: 3
      version:
        description: "  Tag to deploy  "
      target:
        type: environment
''')!;
      expect([for (final i in d.inputs) i.name], ['environment', 'dry_run', 'replicas', 'version', 'target']);
      final [env, dry, replicas, version, target] = d.inputs;
      expect(env.type, DispatchInputType.choice);
      expect(env.required, isTrue);
      expect(env.options, ['staging', 'production']);
      expect(env.initialValue, 'staging', reason: 'a choice without a default starts on the first option');
      expect(dry.type, DispatchInputType.boolean);
      expect(dry.initialValue, 'true');
      expect(replicas.initialValue, '3');
      expect(version.type, DispatchInputType.string);
      expect(version.description, 'Tag to deploy');
      expect(target.type, DispatchInputType.environment);
    });

    test('validates and builds the payload', () {
      final d = parseWorkflowDispatch('''
on:
  workflow_dispatch:
    inputs:
      name: {required: true}
      count: {type: number}
      level: {type: choice, options: [low, high]}
      notify: {type: boolean}
      note: {}
''')!;
      final values = {for (final i in d.inputs) i.name: i.initialValue};
      expect(values, {'name': '', 'count': '', 'level': 'low', 'notify': 'false', 'note': ''});
      expect(d.errors(values), {'name': 'Required'});
      values
        ..['name'] = ' api '
        ..['count'] = 'ten';
      expect(d.errors(values), {'count': 'Must be a number'});
      values['count'] = '10';
      expect(d.errors(values), isEmpty);
      expect(d.payload(values), {'name': 'api', 'count': '10', 'level': 'low', 'notify': 'false'});
    });

    test('a file that is not a workflow', () {
      expect(() => parseWorkflowDispatch('on: [push'), throwsFormatException);
      expect(() => parseWorkflowDispatch('- just a list'), throwsFormatException);
    });
  });

  group('parseJobLog', () {
    test('drops timestamps and colors, folds groups, marks errors', () {
      final lines = parseJobLog(
        '﻿2026-10-12T09:14:02.1000000Z Runner 2.329\r\n'
        '2026-10-12T09:14:02.2000000Z ##[group]Run go test ./...\n'
        '2026-10-12T09:14:02.2000000Z \x1b[36;1mgo test ./...\x1b[0m\n'
        '2026-10-12T09:14:02.3000000Z ##[endgroup]\n'
        '2026-10-12T09:14:03.0000000Z [command]/usr/bin/git log\n'
        '2026-10-12T09:14:04.0000000Z ##[warning]Deprecated\n'
        '2026-10-12T09:14:05.0000000Z ##[error]Process completed with exit code 1.\n',
      );
      expect(
        [for (final l in lines) l.text],
        [
          'Runner 2.329',
          'Run go test ./...',
          'go test ./...',
          '/usr/bin/git log',
          'Deprecated',
          'Process completed with exit code 1.',
        ],
      );
      expect(
        [for (final l in lines) l.kind],
        [LogKind.plain, LogKind.group, LogKind.plain, LogKind.command, LogKind.warning, LogKind.error],
      );
      expect(lines[2].group, 1);
      expect(lines[3].group, isNull);
      expect(visibleLogLines(lines, {}), [0, 1, 3, 4, 5]);
      expect(visibleLogLines(lines, {1}), [0, 1, 2, 3, 4, 5]);
    });

    test('an empty log', () => expect(parseJobLog(''), isEmpty));
  });
}
