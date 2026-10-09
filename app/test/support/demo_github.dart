import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A canned GitHub API with a small, made-up project, for tests that render
/// whole screens (screen-size sweep, device smoke test, store screenshots).
///
/// Every name here is fictional. Unknown paths answer 404 and are recorded in
/// [unknown] so tests can assert the screens only call what's covered.
class DemoGitHub implements HttpClientAdapter {
  DemoGitHub({DateTime? now}) : _now = (now ?? DateTime.now()).toUtc();

  static const owner = 'demo';
  static const repoName = 'payments-api';
  static const repo = (owner: owner, name: repoName);
  static const featureBranch = 'feature/retry-backoff';

  /// Title of the newest commit on main (its detail shows [retryGo]'s diff).
  static String get latestCommitTitle => _commits.first.$1;
  static const openPullNumber = 42;
  static const openPullTitle = 'Exponential backoff for webhook retries';
  static const retryGo = 'internal/webhooks/retry.go';

  final unknown = <String>[];
  final DateTime _now;

  String _ago(Duration d) => _now.subtract(d).toIso8601String();
  static String sha(int i) => (i * 2654435761 % 0xFFFFFFFF).toRadixString(16).padLeft(8, '0') * 5;

  static const _people = [
    ('priya-shah', 'Priya Shah'),
    ('marco-rossi', 'Marco Rossi'),
    ('lena-k', 'Lena Kovač'),
    ('sam-lee', 'Sam Lee'),
  ];

  static const _repos = [
    (repoName, 'Payment processing service with idempotent retries', 'Go', 1, true),
    ('mobile-app', 'Cross-platform shopping app', 'Dart', 5, true),
    ('website', 'Marketing site and docs', 'TypeScript', 26, false),
    ('ml-experiments', 'Notebooks for fraud-detection models', 'Python', 70, true),
    ('infra', 'Terraform modules for staging and production', 'HCL', 150, true),
    ('dotfiles', 'Shell and editor config', 'Shell', 720, false),
  ];

  Map<String, dynamic> _repo((String, String, String, int, bool) r) => {
    'name': r.$1,
    'owner': {'login': owner, 'avatar_url': null},
    'default_branch': 'main',
    'private': r.$5,
    'description': r.$2,
    'language': r.$3,
    'pushed_at': _ago(Duration(hours: r.$4)),
  };

  /// (title, body, author index, hours ago, additions, deletions)
  static const _commits = [
    ('Add exponential backoff to webhook retries', 'Doubles the wait after each failure, with jitter.', 0, 1, 64, 9),
    ('Fix rounding of JPY amounts', 'Zero-decimal currencies were rounded to cents.', 1, 4, 12, 4),
    ('Merge pull request #39 from demo/ledger-batches', 'Reconcile ledger in batches', 2, 9, 118, 40),
    ('Validate idempotency keys on refunds', '', 0, 20, 37, 2),
    ('Log request IDs in error responses', '', 3, 27, 15, 3),
    ('Speed up ledger reconciliation query', 'Adds a partial index on pending entries.', 2, 46, 22, 18),
    ('Bump golang.org/x/net to 0.30.0', '', 3, 70, 3, 3),
    ('Add refund webhook handler', '', 1, 95, 141, 0),
    ('Document the retry policy', '', 0, 120, 48, 6),
    ('Remove deprecated v1 charge endpoint', '', 1, 170, 0, 212),
    ('Cache exchange rates for five minutes', '', 3, 200, 54, 11),
    ('Initial payouts scheduler', '', 2, 260, 330, 0),
  ];

  Map<String, dynamic> _commit(int i, {bool withFiles = false}) {
    final c = _commits[i % _commits.length];
    final person = _people[c.$3];
    return {
      'sha': sha(i + 1),
      'html_url': 'https://github.com/$owner/$repoName/commit/${sha(i + 1)}',
      'commit': {
        'message': c.$2.isEmpty ? c.$1 : '${c.$1}\n\n${c.$2}',
        'author': {'name': person.$2, 'date': _ago(Duration(hours: c.$4))},
      },
      'author': {'login': person.$1, 'avatar_url': null},
      'parents': [
        {'sha': sha(i + 2)},
      ],
      'stats': {'additions': c.$5, 'deletions': c.$6},
      if (withFiles) 'files': _files,
    };
  }

  /// A unified-diff hunk with a header computed from [lines] (' ', '+', '-').
  static String _hunk(int oldStart, int newStart, String context, List<String> lines) {
    final old = lines.where((l) => !l.startsWith('+')).length;
    final added = lines.where((l) => !l.startsWith('-')).length;
    return '@@ -$oldStart,$old +$newStart,$added @@ $context\n${lines.join('\n')}';
  }

  static final _files = [
    {
      'filename': retryGo,
      'status': 'modified',
      'additions': 17,
      'deletions': 3,
      'sha': 'f1',
      'patch': [
        _hunk(12, 12, 'import (', [
          ' // Retrier re-sends webhooks that failed to deliver.',
          ' type Retrier struct {',
          ' \tclient  *http.Client',
          '-\tdelay   time.Duration',
          '+\tbase    time.Duration',
          '+\tmax     time.Duration',
          ' \tretries int',
          ' }',
          ' ',
          '-func (r *Retrier) wait(attempt int) time.Duration {',
          '-\treturn r.delay',
          '+// backoff doubles the wait after each failed attempt, with jitter so',
          '+// failing endpoints don\'t all retry at the same moment.',
          '+func (r *Retrier) backoff(attempt int) time.Duration {',
          '+\td := r.base << attempt',
          '+\tif d > r.max || d <= 0 {',
          '+\t\td = r.max',
          '+\t}',
          '+\treturn d/2 + time.Duration(rand.Int63n(int64(d/2)))',
          ' }',
        ]),
        _hunk(40, 46, 'func (r *Retrier) Deliver(ctx context.Context, hook Webhook) error {', [
          ' \tfor attempt := 0; attempt <= r.retries; attempt++ {',
          ' \t\tif err = r.send(ctx, hook); err == nil {',
          ' \t\t\treturn nil',
          ' \t\t}',
          '+\t\tif !retryable(err) {',
          '+\t\t\treturn err',
          '+\t\t}',
          ' \t\tselect {',
          '-\t\tcase <-time.After(r.wait(attempt)):',
          '+\t\tcase <-time.After(r.backoff(attempt)):',
          ' \t\tcase <-ctx.Done():',
          ' \t\t\treturn ctx.Err()',
          ' \t\t}',
        ]),
      ].join('\n'),
    },
    {
      'filename': 'internal/webhooks/retry_test.go',
      'status': 'added',
      'additions': 14,
      'deletions': 0,
      'sha': 'f2',
      'patch': _hunk(0, 1, '', [
        '+package webhooks',
        '+',
        '+func TestBackoffIsCapped(t *testing.T) {',
        '+\tr := Retrier{base: time.Second, max: time.Minute}',
        '+\tfor attempt := 0; attempt < 20; attempt++ {',
        '+\t\tif d := r.backoff(attempt); d > time.Minute {',
        '+\t\t\tt.Fatalf("attempt %d waited %v", attempt, d)',
        '+\t\t}',
        '+\t}',
        '+}',
      ]),
    },
    {
      'filename': 'docs/retries.md',
      'status': 'modified',
      'additions': 4,
      'deletions': 2,
      'sha': 'f3',
      'patch': _hunk(8, 8, '## Webhook retries', [
        ' Failed deliveries are retried up to 8 times.',
        '-Each retry waits 30 seconds.',
        '-',
        '+Each retry waits twice as long as the one before (1s, 2s, 4s…),',
        '+capped at one minute, plus random jitter.',
        '+',
        '+Errors such as `400 Bad Request` are not retried.',
      ]),
    },
    {'filename': 'docs/retry-timeline.png', 'status': 'added', 'additions': 0, 'deletions': 0, 'sha': 'f4'},
  ];

  /// History of [retryGo] per branch, for the file history graph: main and
  /// two branches forked from it. One main commit is a rebased copy of a
  /// feature commit (same author date and message, new sha); one reverts
  /// another. (id, title, author index, hours since authored, hours since committed)
  static const _retryHistory = {
    'main': [
      (101, 'Revert "Retry on 409 Conflict"', 3, 2, 2),
      (102, 'Add exponential backoff to webhook retries', 0, 30, 5),
      (103, 'Retry on 409 Conflict', 1, 20, 20),
      (104, 'Log request IDs in error responses', 3, 27, 27),
      (105, 'Make retry count configurable', 2, 46, 46),
      (106, 'Add refund webhook handler', 1, 95, 95),
      (107, 'Document the retry policy', 0, 120, 120),
      (108, 'Initial webhook retries', 2, 260, 260),
    ],
    featureBranch: [
      (111, 'Cap backoff at one minute', 0, 3, 3),
      (112, 'Add exponential backoff to webhook retries', 0, 30, 30),
      (105, 'Make retry count configurable', 2, 46, 46),
      (106, 'Add refund webhook handler', 1, 95, 95),
      (107, 'Document the retry policy', 0, 120, 120),
      (108, 'Initial webhook retries', 2, 260, 260),
    ],
    'fix/currency-rounding': [
      (121, 'Honor Retry-After headers', 1, 8, 8),
      (103, 'Retry on 409 Conflict', 1, 20, 20),
      (104, 'Log request IDs in error responses', 3, 27, 27),
      (105, 'Make retry count configurable', 2, 46, 46),
      (106, 'Add refund webhook handler', 1, 95, 95),
      (107, 'Document the retry policy', 0, 120, 120),
      (108, 'Initial webhook retries', 2, 260, 260),
    ],
  };

  List<Map<String, dynamic>>? _fileHistory(String? branch, String path) {
    if (path != retryGo) return [_commit(0)];
    final list = _retryHistory[branch ?? 'main'];
    if (list == null) return null;
    return [
      for (final (i, (id, title, author, authored, committed)) in list.indexed)
        {
          'sha': sha(id),
          'commit': {
            'message': title,
            'author': {'name': _people[author].$2, 'date': _ago(Duration(hours: authored))},
            'committer': {'name': _people[author].$2, 'date': _ago(Duration(hours: committed))},
          },
          'author': {'login': _people[author].$1, 'avatar_url': null},
          'parents': [
            {'sha': i + 1 < list.length ? sha(list[i + 1].$1) : sha(99)},
          ],
        },
    ];
  }

  Map<String, dynamic> _pull(
    int n,
    String title,
    String state,
    int author, {
    String? merged,
    bool draft = false,
    String head = featureBranch,
  }) => {
    'number': n,
    'title': title,
    'body':
        'Webhook endpoints that are briefly down were hammered every 30 seconds.\n\n'
        '- exponential backoff with jitter\n- capped at one minute\n- client errors are not retried',
    'state': state,
    'draft': draft,
    'merged_at': merged,
    'user': {'login': _people[author].$1, 'avatar_url': null},
    'head': {
      'ref': head,
      'sha': sha(1),
      'repo': {'full_name': '$owner/$repoName'},
    },
    'base': {'ref': 'main', 'sha': sha(3)},
    'created_at': _ago(const Duration(hours: 30)),
    'updated_at': _ago(Duration(hours: n == openPullNumber ? 1 : 50)),
    'additions': 35,
    'deletions': 5,
    'changed_files': _files.length,
    'commits': 2,
    'html_url': 'https://github.com/$owner/$repoName/pull/$n',
  };

  List<Map<String, dynamic>> get _pulls => [
    _pull(openPullNumber, openPullTitle, 'open', 0),
    _pull(41, 'Round zero-decimal currencies to whole units', 'open', 1, draft: true, head: 'fix/currency-rounding'),
    _pull(39, 'Reconcile ledger in batches', 'closed', 2, merged: _ago(const Duration(hours: 9))),
    _pull(37, 'Try a Redis-backed rate limiter', 'closed', 3),
  ];

  static const _tree = [
    '.github/workflows/ci.yml',
    'Makefile',
    'README.md',
    'cmd/server/main.go',
    'docs/retries.md',
    'docs/retry-timeline.png',
    'go.mod',
    'go.sum',
    'internal/ledger/reconcile.go',
    'internal/ledger/reconcile_test.go',
    'internal/payments/charge.go',
    'internal/payments/refund.go',
    'internal/webhooks/handler.go',
    'internal/webhooks/retry.go',
    'internal/webhooks/retry_test.go',
  ];

  static const _readme =
      '# payments-api\n\nPayment processing service with idempotent retries.\n\n'
      '## Run locally\n\n```sh\nmake dev\n```\n\n## Layout\n\n'
      '- `cmd/server`: HTTP entry point\n- `internal/payments`: charges and refunds\n'
      '- `internal/webhooks`: delivery and retries\n';

  static const _retrySource = '''package webhooks

import (
\t"context"
\t"math/rand"
\t"net/http"
\t"time"
)

// Retrier re-sends webhooks that failed to deliver.
type Retrier struct {
\tclient  *http.Client
\tbase    time.Duration
\tmax     time.Duration
\tretries int
}

// backoff doubles the wait after each failed attempt, with jitter so
// failing endpoints don't all retry at the same moment.
func (r *Retrier) backoff(attempt int) time.Duration {
\td := r.base << attempt
\tif d > r.max || d <= 0 {
\t\td = r.max
\t}
\treturn d/2 + time.Duration(rand.Int63n(int64(d/2)))
}

// Deliver sends hook, retrying transient failures until ctx is done.
func (r *Retrier) Deliver(ctx context.Context, hook Webhook) error {
\tvar err error
\tfor attempt := 0; attempt <= r.retries; attempt++ {
\t\tif err = r.send(ctx, hook); err == nil {
\t\t\treturn nil
\t\t}
\t\tif !retryable(err) {
\t\t\treturn err
\t\t}
\t\tselect {
\t\tcase <-time.After(r.backoff(attempt)):
\t\tcase <-ctx.Done():
\t\t\treturn ctx.Err()
\t\t}
\t}
\treturn err
}
''';

  /// GraphQL: blame of [retryGo] (any other file: one range).
  Object? _graphql(Object? body) {
    final vars = (body as Map<String, dynamic>?)?['variables'] as Map<String, dynamic>? ?? const {};
    final lines = '\n'.allMatches(_retrySource).length;
    Map<String, dynamic> range(int start, int end, int id, int age) {
      final (_, title, author, _, hours) = _retryHistory['main']!.firstWhere((c) => c.$1 == id);
      return {
        'startingLine': start,
        'endingLine': end,
        'age': age,
        'commit': {
          'oid': sha(id),
          'messageHeadline': title,
          'committedDate': _ago(Duration(hours: hours)),
          'author': {
            'name': _people[author].$2,
            'user': {'login': _people[author].$1},
          },
        },
      };
    }

    final ranges = vars['path'] == retryGo
        ? [range(1, 9, 108, 9), range(10, 16, 105, 6), range(17, 26, 102, 2), range(27, lines, 103, 4)]
        : [range(1, 200, 107, 7)];
    return {
      'data': {
        'repository': {
          'object': {
            'blame': {'ranges': ranges},
          },
        },
      },
    };
  }

  Object? _route(String path, Map<String, dynamic> query) {
    const base = '/repos/$owner/$repoName';
    if (path == '/user') return {'login': owner, 'name': 'Demo Developer', 'avatar_url': null};
    if (path == '/user/repos') return [for (final r in _repos) _repo(r)];
    for (final r in _repos) {
      if (path.toLowerCase() == '/repos/$owner/${r.$1}'.toLowerCase()) return _repo(r);
    }
    if (path == '$base/branches') {
      return [
        for (final (i, b) in ['main', featureBranch, 'fix/currency-rounding', 'ledger-batches'].indexed)
          {
            'name': b,
            'commit': {'sha': sha(i * 3 + 1)},
          },
      ];
    }
    if (path == '$base/tags') {
      return [
        for (final (i, t) in ['v1.4.0', 'v1.3.2', 'v1.3.1'].indexed)
          {
            'name': t,
            'commit': {'sha': sha(i * 4 + 3)},
          },
      ];
    }
    if (path == '$base/commits' && query['path'] != null) {
      return _fileHistory(query['sha'] as String?, '${query['path']}');
    }
    if (path == '$base/commits') {
      final perPage = int.tryParse('${query['per_page'] ?? ''}') ?? 30;
      return [for (var i = 0; i < _commits.length && i < perPage; i++) _commit(i)];
    }
    if (path.startsWith('$base/commits/')) return _commit(0, withFiles: true);
    if (path.startsWith('$base/compare/')) {
      return {
        'status': 'ahead',
        'ahead_by': 2,
        'behind_by': 0,
        'total_commits': 2,
        'merge_base_commit': {'sha': sha(3)},
        'commits': [_commit(1), _commit(0)],
        'files': _files,
      };
    }
    if (path.startsWith('$base/git/trees/')) {
      final dirs = {
        for (final f in _tree)
          for (var i = 1; i < f.split('/').length; i++) f.split('/').take(i).join('/'),
      };
      return {
        'sha': sha(1),
        'truncated': false,
        'tree': [
          for (final d in dirs) {'path': d, 'type': 'tree', 'sha': 't-$d'},
          for (final f in _tree) {'path': f, 'type': 'blob', 'sha': 'b-$f', 'size': 400 + f.length * 97},
        ],
      };
    }
    if (path.startsWith('$base/contents/')) {
      return path.endsWith('.go') ? _retrySource : _readme;
    }
    if (path == '$base/pulls') return _pulls;
    final pull = RegExp(r'/pulls/(\d+)(/\w+)?$').firstMatch(path);
    if (pull != null) {
      final n = int.parse(pull.group(1)!);
      final p = _pulls.firstWhere((p) => p['number'] == n, orElse: () => _pulls.first);
      return switch (pull.group(2)) {
        null => p,
        '/files' => _files,
        '/commits' => [_commit(1), _commit(0)],
        _ => null,
      };
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.path == '/graphql' ? _graphql(options.data) : _route(options.path, options.queryParameters);
    if (data == null) {
      unknown.add(options.path);
      return ResponseBody.fromString(
        jsonEncode({'message': 'Not Found'}),
        404,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }
    final isRaw = data is String;
    return ResponseBody.fromString(
      isRaw ? data : jsonEncode(data),
      200,
      headers: {
        'content-type': [isRaw ? 'text/plain' : 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
