import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/files/history_graph.dart';

final _t0 = DateTime.utc(2026, 10, 1);

/// A commit [hours] after t0 (committed [committed] hours after t0 if given).
GhCommit c(String sha, int hours, {String? title, int? committed, String author = 'Ann', int parents = 1}) => GhCommit(
  sha: sha,
  message: title ?? 'Commit $sha',
  authorName: author,
  date: _t0.add(Duration(hours: hours)),
  committedDate: _t0.add(Duration(hours: committed ?? hours)),
  parents: List.filled(parents, 'p'),
);

List<String> shas(HistoryGraph g) => [for (final r in g.rows) r.node.sha];

/// Segments of a row as compact strings: `|c` pass, `^c` in, `vc` out (`:` = dashed).
List<String> segs(HistoryGraph g, String sha) => [
  for (final s in g.rows[g.rowOf(sha)!].segments)
    '${switch (s) {
      PassSegment() => '|',
      InSegment() => '^',
      OutSegment() => 'v',
    }}${s.column}${s.dashed ? ':' : ''}',
];

void main() {
  test('a single branch is one straight lane', () {
    final g = buildHistoryGraph([
      BranchLog('main', [c('c', 3), c('b', 2), c('a', 1)]),
    ]);
    expect(shas(g), ['c', 'b', 'a']);
    expect(g.columns, 1);
    expect(segs(g, 'c'), ['v0']);
    expect(segs(g, 'b'), unorderedEquals(['v0', '^0']));
    expect(segs(g, 'a'), ['^0']);
    expect(g.rows.first.node.tips, ['main']);
    expect(g.lanes.single.ownCommits, 3);
  });

  test('a branch forks off the base where its own work starts', () {
    final g = buildHistoryGraph([
      BranchLog('main', [c('m3', 5), c('m2', 3), c('m1', 1)]),
      BranchLog('feature', [c('f2', 4), c('f1', 2), c('m1', 1)]),
    ]);
    expect(shas(g), ['m3', 'f2', 'm2', 'f1', 'm1']);
    expect(g.columns, 2);
    final feature = g.lanes[1];
    expect(feature.column, 1);
    expect(feature.ownCommits, 2);
    expect(feature.forkSha, 'm1');
    expect(g.rows[g.rowOf('f2')!].node.column, 1);
    // f1's line goes down column 1 and curves into m1 in column 0.
    expect(segs(g, 'f1'), contains('v1'));
    expect(segs(g, 'm1'), containsAll(['^0', '^1']));
    // The base lane passes beside the branch.
    expect(segs(g, 'f2'), unorderedEquals(['v1', '|0']));
    expect(g.rows.first.node.tips, ['main']);
    expect(g.rows[1].node.tips, ['feature']);
  });

  test('a merged branch has no lane of its own, only its tip label', () {
    final g = buildHistoryGraph([
      BranchLog('main', [c('m', 5, parents: 2), c('f1', 3), c('a', 1)]),
      BranchLog('feature', [c('f1', 3), c('a', 1)]),
    ]);
    expect(g.columns, 1);
    expect(g.lanes[1].column, isNull);
    expect(g.lanes[1].ownCommits, 0);
    expect(g.rows[g.rowOf('f1')!].node.tips, ['feature']);
  });

  test('rebased copies link to their original with a dashed line', () {
    final g = buildHistoryGraph([
      BranchLog('main', [c('copy', 2, title: 'Backoff', committed: 9), c('m1', 1)]),
      BranchLog('feature', [c('orig', 2, title: 'Backoff'), c('m1', 1)]),
    ]);
    expect(shas(g), ['copy', 'orig', 'm1']);
    final copy = g.rows[0].node;
    final orig = g.rows[1].node;
    expect(copy.copyOf?.sha, 'orig');
    expect(copy.copyOfLane, 1);
    expect(orig.copies.map((c) => c.sha), ['copy']);
    expect(g.lanes[1].copiedCommits, 1);
    // Link column after the two lanes.
    expect(g.columns, 3);
    expect(segs(g, 'copy'), contains('v2:'));
    expect(segs(g, 'orig'), contains('^2:'));
  });

  test('copies need the same message, author and author date', () {
    final g = buildHistoryGraph([
      BranchLog('main', [
        c('a', 2, title: 'Same'),
        c('b', 1, title: 'Same', author: 'Bob'),
        c('d', 2, title: 'Same', committed: 0),
      ]),
    ]);
    expect(g.rows.where((r) => r.node.copyOf != null).map((r) => r.node.sha), ['a']);
  });

  test('reverts link to the reverted commit', () {
    final g = buildHistoryGraph([
      BranchLog('main', [c('r', 3, title: 'Revert "Risky"'), c('x', 2, title: 'Risky'), c('a', 1)]),
    ]);
    expect(g.rows[0].node.reverts?.sha, 'x');
    expect(g.rows[1].node.revertedBy?.sha, 'r');
    expect(segs(g, 'r'), contains('v1:'));
    expect(g.rows[0].segments.whereType<OutSegment>().where((s) => s.dashed).single.color, -1);
  });

  test('link columns are reused once free and capped', () {
    final g = buildHistoryGraph([
      BranchLog('main', [
        c('r1', 9, title: 'Revert "A"'),
        c('a', 8, title: 'A'),
        c('r2', 7, title: 'Revert "B"'),
        c('b', 6, title: 'B'),
        c('r3', 5, title: 'Revert "C"'),
        c('r4', 4, title: 'Revert "D"'),
        c('r5', 3, title: 'Revert "E"'),
        c('cc', 2, title: 'C'),
        c('d', 1, title: 'D'),
        c('e', 0, title: 'E'),
      ]),
    ]);
    // r1→a and r2→b share column 1; r3→c takes 1, r4→d needs 2, r5→e has no room.
    expect(segs(g, 'r2'), contains('v1:'));
    expect(g.columns, 1 + maxLinkColumns);
    expect(g.rows[g.rowOf('r5')!].node.reverts?.sha, 'e', reason: 'the badge stays without a line');
    expect(segs(g, 'r5').where((s) => s.endsWith(':') && s.startsWith('v')), isEmpty);
  });

  test('rows older than an unfinished log are hidden and its line continues', () {
    final g = buildHistoryGraph([
      BranchLog('main', [c('m2', 6), c('m1', 1)]),
      BranchLog('feature', [c('f2', 5), c('f1', 4)], complete: false),
    ]);
    expect(shas(g), ['m2', 'f2', 'f1']);
    expect(g.truncated, isTrue);
    // m2's next commit (m1) is hidden: the lane runs off the bottom.
    expect(segs(g, 'f1'), containsAll(['^1', '|0']));
    expect(segs(g, 'f1'), contains('v1'));
  });

  test('a branch forked from another branch joins that branch', () {
    final g = buildHistoryGraph([
      BranchLog('main', [c('m1', 1)]),
      BranchLog('a', [c('a1', 2), c('m1', 1)]),
      BranchLog('b', [c('b1', 3), c('a1', 2), c('m1', 1)]),
    ]);
    expect(g.lanes[2].forkSha, 'a1');
    expect(segs(g, 'a1'), containsAll(['^2', 'v1']));
  });

  test('empty input', () {
    expect(buildHistoryGraph(const []).rows, isEmpty);
    final g = buildHistoryGraph([const BranchLog('main', []), const BranchLog('gone', [])]);
    expect(g.rows, isEmpty);
    expect(g.lanes[1].column, isNull);
  });
}
