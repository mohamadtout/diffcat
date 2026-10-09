import 'file_change.dart';

class GhCommit {
  const GhCommit({
    required this.sha,
    required this.message,
    required this.authorName,
    required this.date,
    required this.parents,
    DateTime? committedDate,
    this.authorLogin,
    this.authorAvatarUrl,
    this.additions,
    this.deletions,
    this.files = const [],
    this.htmlUrl,
  }) : committedDate = committedDate ?? date;

  factory GhCommit.fromJson(Map<String, dynamic> j) {
    final commit = j['commit'] as Map<String, dynamic>;
    final author = commit['author'] as Map<String, dynamic>?;
    final committer = commit['committer'] as Map<String, dynamic>?;
    final ghAuthor = j['author'] as Map<String, dynamic>?;
    final stats = j['stats'] as Map<String, dynamic>?;
    final files = j['files'] as List<dynamic>?;
    return GhCommit(
      sha: j['sha'] as String,
      message: (commit['message'] as String?) ?? '',
      authorName: (author?['name'] as String?) ?? 'unknown',
      date: DateTime.tryParse((author?['date'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      committedDate: DateTime.tryParse((committer?['date'] as String?) ?? ''),
      parents: [
        for (final p in (j['parents'] as List<dynamic>? ?? const [])) (p as Map<String, dynamic>)['sha'] as String,
      ],
      authorLogin: ghAuthor?['login'] as String?,
      authorAvatarUrl: ghAuthor?['avatar_url'] as String?,
      additions: stats?['additions'] as int?,
      deletions: stats?['deletions'] as int?,
      files: [for (final f in files ?? const <dynamic>[]) GhFileChange.fromJson(f as Map<String, dynamic>)],
      htmlUrl: j['html_url'] as String?,
    );
  }

  final String sha;
  final String message;
  final String authorName;
  final String? authorLogin;
  final String? authorAvatarUrl;

  /// When it was authored. A rebase or cherry-pick keeps this.
  final DateTime date;

  /// When it was committed (equal to [date] unless rebased, amended or
  /// cherry-picked). History is ordered by this.
  final DateTime committedDate;
  final List<String> parents;
  final int? additions;
  final int? deletions;

  /// Only populated for single-commit fetches.
  final List<GhFileChange> files;
  final String? htmlUrl;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
  String get title => message.split('\n').first;
  String get body {
    final i = message.indexOf('\n');
    return i < 0 ? '' : message.substring(i + 1).trim();
  }

  bool get isMerge => parents.length > 1;

  GhCommit copyWith({List<GhFileChange>? files}) => GhCommit(
    sha: sha,
    message: message,
    authorName: authorName,
    authorLogin: authorLogin,
    authorAvatarUrl: authorAvatarUrl,
    date: date,
    committedDate: committedDate,
    parents: parents,
    additions: additions,
    deletions: deletions,
    files: files ?? this.files,
    htmlUrl: htmlUrl,
  );
}

class GhCompare {
  const GhCompare({
    required this.status,
    required this.aheadBy,
    required this.behindBy,
    required this.totalCommits,
    required this.commits,
    required this.files,
    this.mergeBaseSha,
  });

  factory GhCompare.fromJson(Map<String, dynamic> j) => GhCompare(
    status: (j['status'] as String?) ?? 'unknown',
    aheadBy: (j['ahead_by'] as int?) ?? 0,
    behindBy: (j['behind_by'] as int?) ?? 0,
    totalCommits: (j['total_commits'] as int?) ?? 0,
    mergeBaseSha: (j['merge_base_commit'] as Map<String, dynamic>?)?['sha'] as String?,
    commits: [
      for (final c in (j['commits'] as List<dynamic>? ?? const [])) GhCommit.fromJson(c as Map<String, dynamic>),
    ],
    files: [
      for (final f in (j['files'] as List<dynamic>? ?? const [])) GhFileChange.fromJson(f as Map<String, dynamic>),
    ],
  );

  final String status;
  final int aheadBy;
  final int behindBy;
  final int totalCommits;
  final List<GhCommit> commits;
  final List<GhFileChange> files;
  final String? mergeBaseSha;

  /// GitHub caps compare responses at 300 files.
  bool get filesTruncated => files.length >= 300;
}
