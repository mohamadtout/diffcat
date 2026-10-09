import 'repo.dart';

/// Which version of the file a review comment sits on.
enum DiffSide {
  /// The new version (added and unchanged lines).
  right,

  /// The old version (removed lines).
  left;

  String get api => name.toUpperCase();
  static DiffSide parse(Object? s) => s == 'LEFT' ? left : right;
}

/// A comment on a line of a pull request's diff.
class GhReviewComment {
  const GhReviewComment({
    required this.id,
    required this.path,
    required this.side,
    required this.body,
    required this.user,
    required this.createdAt,
    this.line,
    this.inReplyToId,
    this.htmlUrl,
  });

  factory GhReviewComment.fromJson(Map<String, dynamic> j) => GhReviewComment(
    id: j['id'] as int,
    path: j['path'] as String,
    line: j['line'] as int?,
    side: DiffSide.parse(j['side']),
    body: (j['body'] as String?) ?? '',
    user: GhUser.fromJson(j['user'] as Map<String, dynamic>),
    createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    inReplyToId: j['in_reply_to_id'] as int?,
    htmlUrl: j['html_url'] as String?,
  );

  final int id;
  final String path;

  /// Null when the code it was on has since changed (outdated).
  final int? line;
  final DiffSide side;
  final String body;
  final GhUser user;
  final DateTime createdAt;
  final int? inReplyToId;
  final String? htmlUrl;
}

enum ReviewState { approved, changesRequested, commented, dismissed, pending }

/// A submitted review: its verdict and summary.
class GhReview {
  const GhReview({required this.id, required this.user, required this.state, required this.body, this.submittedAt});

  factory GhReview.fromJson(Map<String, dynamic> j) => GhReview(
    id: j['id'] as int,
    user: GhUser.fromJson(j['user'] as Map<String, dynamic>),
    state: switch (j['state']) {
      'APPROVED' => ReviewState.approved,
      'CHANGES_REQUESTED' => ReviewState.changesRequested,
      'DISMISSED' => ReviewState.dismissed,
      'PENDING' => ReviewState.pending,
      _ => ReviewState.commented,
    },
    body: (j['body'] as String?) ?? '',
    submittedAt: DateTime.tryParse((j['submitted_at'] as String?) ?? ''),
  );

  final int id;
  final GhUser user;
  final ReviewState state;
  final String body;
  final DateTime? submittedAt;
}

/// What submitting a review says about the pull request.
enum ReviewEvent {
  comment('COMMENT', 'Comment'),
  approve('APPROVE', 'Approve'),
  requestChanges('REQUEST_CHANGES', 'Request changes');

  const ReviewEvent(this.api, this.label);
  final String api;
  final String label;
}
