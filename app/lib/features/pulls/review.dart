import '../../data/github/models/models.dart';
import '../diff/diff_parser.dart';

/// Where a comment goes in a diff: a file, a side and a line number on it.
typedef LineAnchor = ({String path, DiffSide side, int line});

/// The anchor GitHub uses for [line]: removed lines are on the old side
/// (their old number), everything else on the new side. Null for lines that
/// can't take comments ("\ No newline at end of file").
LineAnchor? anchorFor(String path, DiffLine line) => switch (line.kind) {
  DiffLineKind.delete when line.oldNo != null => (path: path, side: DiffSide.left, line: line.oldNo!),
  DiffLineKind.add ||
  DiffLineKind.context when line.newNo != null => (path: path, side: DiffSide.right, line: line.newNo!),
  _ => null,
};

/// A comment and its replies.
class ReviewThread {
  ReviewThread(this.root);

  final GhReviewComment root;
  final replies = <GhReviewComment>[];
}

/// Threads by the line they're on. Comments on code that has since changed
/// (no line) are left out; [outdatedCount] counts their threads.
({Map<LineAnchor, List<ReviewThread>> byLine, int outdatedCount}) threadComments(List<GhReviewComment> comments) {
  final roots = <int, ReviewThread>{};
  final byLine = <LineAnchor, List<ReviewThread>>{};
  var outdated = 0;
  final sorted = [...comments]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  for (final c in sorted) {
    final parent = c.inReplyToId == null ? null : roots[c.inReplyToId];
    if (parent != null) {
      parent.replies.add(c);
      roots[c.id] = parent; // replies to replies join the same thread
      continue;
    }
    final thread = roots[c.id] = ReviewThread(c);
    if (c.line == null) {
      outdated++;
    } else {
      (byLine[(path: c.path, side: c.side, line: c.line!)] ??= []).add(thread);
    }
  }
  return (byLine: byLine, outdatedCount: outdated);
}

/// Each reviewer's current verdict: their latest approve / request changes
/// (a later plain comment doesn't undo it), else that they commented.
Map<String, ReviewState> reviewerStates(List<GhReview> reviews) {
  final out = <String, ReviewState>{};
  for (final r in reviews) {
    final login = r.user.login;
    switch (r.state) {
      case ReviewState.approved || ReviewState.changesRequested || ReviewState.dismissed:
        out[login] = r.state;
      case ReviewState.commented:
        out.putIfAbsent(login, () => ReviewState.commented);
      case ReviewState.pending:
        break;
    }
  }
  return out;
}

/// A comment written but not yet submitted.
class DraftComment {
  const DraftComment({required this.anchor, required this.body});

  factory DraftComment.fromJson(Map<String, dynamic> j) => DraftComment(
    anchor: (path: j['path'] as String, side: DiffSide.parse(j['side']), line: j['line'] as int),
    body: j['body'] as String,
  );

  final LineAnchor anchor;
  final String body;

  Map<String, dynamic> toJson() => {'path': anchor.path, 'side': anchor.side.api, 'line': anchor.line, 'body': body};
}

/// A review in progress on one pull request: comments and summary, and the
/// head commit they were written against. Kept on the device until
/// submitted, so it survives restarts and works offline.
class ReviewDraft {
  const ReviewDraft({this.headSha, this.comments = const [], this.body = ''});

  factory ReviewDraft.fromJson(Map<String, dynamic> j) => ReviewDraft(
    headSha: j['headSha'] as String?,
    comments: [
      for (final c in (j['comments'] as List<dynamic>? ?? const [])) DraftComment.fromJson(c as Map<String, dynamic>),
    ],
    body: (j['body'] as String?) ?? '',
  );

  final String? headSha;
  final List<DraftComment> comments;
  final String body;

  bool get isEmpty => comments.isEmpty && body.trim().isEmpty;

  ReviewDraft copyWith({String? headSha, List<DraftComment>? comments, String? body}) =>
      ReviewDraft(headSha: headSha ?? this.headSha, comments: comments ?? this.comments, body: body ?? this.body);

  Map<String, dynamic> toJson() => {
    'headSha': headSha,
    'comments': [for (final c in comments) c.toJson()],
    'body': body,
  };

  /// The `comments` of a review submission.
  List<Map<String, dynamic>> apiComments() => [
    for (final c in comments) {'path': c.anchor.path, 'line': c.anchor.line, 'side': c.anchor.side.api, 'body': c.body},
  ];
}
