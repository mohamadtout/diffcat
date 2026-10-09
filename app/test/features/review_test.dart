import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/diff/diff_parser.dart';
import 'package:git_reviewer/features/pulls/review.dart';

GhReviewComment _c(int id, {int? line = 3, int? replyTo, int minutes = 0, String path = 'a.dart'}) => GhReviewComment(
  id: id,
  path: path,
  line: line,
  side: DiffSide.right,
  body: 'c$id',
  user: const GhUser(login: 'u'),
  createdAt: DateTime(2026).add(Duration(minutes: minutes)),
  inReplyToId: replyTo,
);

GhReview _r(String login, ReviewState s) => GhReview(
  id: 0,
  user: GhUser(login: login),
  state: s,
  body: '',
);

void main() {
  test('comments anchor to the new side, removed lines to the old side', () {
    final lines = parsePatch('@@ -10,2 +10,2 @@\n ctx\n-old\n+new\n\\ No newline at end of file')[0].lines;
    expect(anchorFor('a', lines[0]), (path: 'a', side: DiffSide.right, line: 10));
    expect(anchorFor('a', lines[1]), (path: 'a', side: DiffSide.left, line: 11));
    expect(anchorFor('a', lines[2]), (path: 'a', side: DiffSide.right, line: 11));
    expect(anchorFor('a', lines[3]), isNull);
  });

  test('threads: replies (and replies to replies) join their root; outdated ones are counted', () {
    final t = threadComments([
      _c(3, replyTo: 2, minutes: 3),
      _c(1),
      _c(2, replyTo: 1, minutes: 1),
      _c(4, line: null, minutes: 5),
      _c(5, path: 'b.dart', minutes: 6),
    ]);
    final a = t.byLine[(path: 'a.dart', side: DiffSide.right, line: 3)]!;
    expect(a.single.root.id, 1);
    expect(a.single.replies.map((c) => c.id), [2, 3]);
    expect(t.outdatedCount, 1);
    expect(t.byLine, hasLength(2));
  });

  test('a reviewer keeps their latest verdict; a later comment does not undo it', () {
    final s = reviewerStates([
      _r('ann', ReviewState.changesRequested),
      _r('bob', ReviewState.commented),
      _r('ann', ReviewState.approved),
      _r('ann', ReviewState.commented),
      _r('cy', ReviewState.pending),
    ]);
    expect(s, {'ann': ReviewState.approved, 'bob': ReviewState.commented});
  });

  test('drafts survive JSON and become API comments', () {
    const d = ReviewDraft(
      headSha: 'abc',
      body: 'Looks good',
      comments: [DraftComment(anchor: (path: 'a.dart', side: DiffSide.left, line: 4), body: 'why?')],
    );
    final back = ReviewDraft.fromJson(d.toJson());
    expect(back.headSha, 'abc');
    expect(back.comments.single.anchor, (path: 'a.dart', side: DiffSide.left, line: 4));
    expect(back.apiComments(), [
      {'path': 'a.dart', 'line': 4, 'side': 'LEFT', 'body': 'why?'},
    ]);
    expect(const ReviewDraft().isEmpty, isTrue);
  });
}
