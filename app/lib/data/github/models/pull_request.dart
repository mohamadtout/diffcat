import 'repo.dart';

enum PullState { open, closed, merged, draft }

class GhPull {
  const GhPull({
    required this.number,
    required this.title,
    required this.body,
    required this.state,
    required this.author,
    required this.headRef,
    required this.headSha,
    required this.baseRef,
    required this.createdAt,
    required this.updatedAt,
    this.additions,
    this.deletions,
    this.changedFiles,
    this.commits,
    this.htmlUrl,
  });

  factory GhPull.fromJson(Map<String, dynamic> j) {
    final head = j['head'] as Map<String, dynamic>;
    final base = j['base'] as Map<String, dynamic>;
    final merged = (j['merged_at'] as String?) != null;
    final draft = (j['draft'] as bool?) ?? false;
    final open = j['state'] == 'open';
    return GhPull(
      number: j['number'] as int,
      title: (j['title'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      state: merged
          ? PullState.merged
          : !open
          ? PullState.closed
          : draft
          ? PullState.draft
          : PullState.open,
      author: GhUser.fromJson(j['user'] as Map<String, dynamic>),
      headRef: head['ref'] as String,
      headSha: head['sha'] as String,
      baseRef: base['ref'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      updatedAt: DateTime.parse(j['updated_at'] as String),
      additions: j['additions'] as int?,
      deletions: j['deletions'] as int?,
      changedFiles: j['changed_files'] as int?,
      commits: j['commits'] as int?,
      htmlUrl: j['html_url'] as String?,
    );
  }

  final int number;
  final String title;
  final String body;
  final PullState state;
  final GhUser author;
  final String headRef;
  final String headSha;
  final String baseRef;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Only present on single-PR fetches.
  final int? additions;
  final int? deletions;
  final int? changedFiles;
  final int? commits;
  final String? htmlUrl;
}
