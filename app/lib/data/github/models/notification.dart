import 'repo.dart';

/// One thread of the user's GitHub notifications inbox (`GET /notifications`).
class GhNotification {
  const GhNotification({
    required this.id,
    required this.repo,
    required this.reason,
    required this.unread,
    required this.updatedAt,
    required this.title,
    required this.type,
    this.number,
  });

  factory GhNotification.fromJson(Map<String, dynamic> j) {
    final subject = j['subject'] as Map<String, dynamic>? ?? const {};
    final fullName = ((j['repository'] as Map<String, dynamic>?)?['full_name'] as String?) ?? '/';
    final slash = fullName.indexOf('/');
    // https://api.github.com/repos/<owner>/<name>/pulls/<number>
    final number = RegExp(r'/(?:pulls|issues)/(\d+)$').firstMatch((subject['url'] as String?) ?? '')?[1];
    return GhNotification(
      id: '${j['id']}',
      repo: (owner: fullName.substring(0, slash), name: fullName.substring(slash + 1)),
      reason: (j['reason'] as String?) ?? '',
      unread: (j['unread'] as bool?) ?? false,
      updatedAt: DateTime.tryParse((j['updated_at'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      title: (subject['title'] as String?) ?? '',
      type: (subject['type'] as String?) ?? '',
      number: number == null ? null : int.parse(number),
    );
  }

  final String id;
  final RepoRef repo;

  /// Why it's in the inbox: `review_requested`, `mention`, `comment`…
  final String reason;
  final bool unread;
  final DateTime updatedAt;
  final String title;

  /// `PullRequest`, `Issue`, `Release`, `CheckSuite`…
  final String type;

  /// Pull request or issue number.
  final int? number;
}
