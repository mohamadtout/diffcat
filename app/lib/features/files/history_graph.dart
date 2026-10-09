import '../../data/github/models/models.dart';

/// One branch's history of a file (`git log <branch> -- <path>`), newest first.
class BranchLog {
  const BranchLog(this.name, this.commits, {this.complete = true});

  final String name;
  final List<GhCommit> commits;

  /// False while older pages exist. Rows older than this log's oldest commit
  /// are then left out, since this branch's part of them isn't known yet.
  final bool complete;
}

/// A branch in the graph. Lane 0 is the branch the history was opened on.
class GraphLane {
  const GraphLane({
    required this.index,
    required this.name,
    required this.column,
    required this.ownCommits,
    required this.copiedCommits,
    this.forkSha,
  });

  final int index;
  final String name;

  /// Column it's drawn in, or null when it has no commits of its own (its
  /// history of this file is entirely shared with another lane).
  final int? column;

  /// Commits that change this file and are on this branch only.
  final int ownCommits;

  /// How many of [ownCommits] also landed elsewhere as rebased or
  /// cherry-picked copies.
  final int copiedCommits;

  /// The commit this branch's own work starts from.
  final String? forkSha;

  bool get isBase => index == 0;
}

/// How a dashed link relates two commits.
enum LinkKind {
  /// Same change re-applied by a rebase or cherry-pick (same message, author
  /// and author date, different sha).
  copy,

  /// `Revert "<title>"`.
  revert,
}

/// A commit placed in the graph.
class GraphNode {
  GraphNode(this.commit, {required this.lane, required this.column});

  final GhCommit commit;
  final int lane;
  final int column;

  /// Branches whose newest change to the file is this commit (`git log --decorate`).
  final tips = <String>[];

  /// Set on rebased/cherry-picked copies: the original commit and its lane.
  GhCommit? copyOf;
  int? copyOfLane;

  /// Set on copied originals: where the copies are.
  final copies = <GhCommit>[];

  /// Set on reverts: the reverted commit, when it's in the graph.
  GhCommit? reverts;

  /// Set on reverted commits.
  GhCommit? revertedBy;

  String get sha => commit.sha;
}

/// What to draw in a row's graph gutter. Every edge between two nodes is
/// split into per-row pieces so a lazily built list can paint row by row.
sealed class GraphSegment {
  const GraphSegment(this.column, this.color, {this.dashed = false});

  /// Column the line travels in (outside the node's own column for curves).
  final int column;

  /// Lane index for the color, or -1 for a revert link.
  final int color;
  final bool dashed;
}

/// A line through the whole row.
class PassSegment extends GraphSegment {
  const PassSegment(super.column, super.color, {super.dashed});
}

/// From the row's top edge at [column] into the node.
class InSegment extends GraphSegment {
  const InSegment(super.column, super.color, {super.dashed});
}

/// From the node to the row's bottom edge at [column].
class OutSegment extends GraphSegment {
  const OutSegment(super.column, super.color, {super.dashed});
}

class GraphRow {
  GraphRow(this.node);

  final GraphNode node;
  final segments = <GraphSegment>[];
}

/// A file's history across several branches, laid out like `git log --graph`.
class HistoryGraph {
  const HistoryGraph({required this.lanes, required this.rows, required this.columns, required this.truncated});

  final List<GraphLane> lanes;
  final List<GraphRow> rows;
  final int columns;

  /// Some logs have older pages that aren't loaded (and rows older than
  /// their oldest loaded commit are hidden).
  final bool truncated;

  int? rowOf(String sha) {
    final i = rows.indexWhere((r) => r.sha == sha);
    return i < 0 ? null : i;
  }
}

extension on GraphRow {
  String get sha => node.sha;
}

/// Dashed links beyond this many columns are dropped (the badges remain).
const maxLinkColumns = 2;

final _revertTitle = RegExp(r'^Revert "(.+)"$');

/// Lays out [logs] (the first one is the base branch) as a graph:
///
/// - Rows are every distinct commit, newest commit date first.
/// - A commit belongs to the base lane if the base branch has it, otherwise
///   to the first other branch that does. A branch with commits of its own
///   gets a column; its line runs from its newest commit down to the commit
///   its work started from, where it joins the lane that commit is in.
/// - Commits with the same message, author and author date but different
///   shas are rebased or cherry-picked copies: a dashed link joins each copy
///   to the original (the oldest by commit date).
/// - `Revert "X"` gets a dashed link to the commit titled X.
///
/// Git doesn't record branches on commits, so for a branch that was merged
/// (all its commits are in the base) this shows the merged result: its
/// commits sit in the base lane and the branch only appears as a tip label.
HistoryGraph buildHistoryGraph(List<BranchLog> logs) {
  if (logs.isEmpty) return const HistoryGraph(lanes: [], rows: [], columns: 0, truncated: false);

  // Distinct commits, the order they were first seen and which logs have them.
  final commits = <String, GhCommit>{};
  final seen = <String, int>{};
  final inLogs = <String, Set<int>>{};
  for (final (li, log) in logs.indexed) {
    for (final c in log.commits) {
      commits.putIfAbsent(c.sha, () => c);
      seen.putIfAbsent(c.sha, () => seen.length);
      (inLogs[c.sha] ??= {}).add(li);
    }
  }

  // Hide what's older than the oldest loaded commit of an unfinished log.
  DateTime? cutoff;
  for (final log in logs) {
    if (log.complete || log.commits.isEmpty) continue;
    final oldest = log.commits.last.committedDate;
    if (cutoff == null || oldest.isAfter(cutoff)) cutoff = oldest;
  }
  final visible = commits.values.where((c) => cutoff == null || !c.committedDate.isBefore(cutoff)).toList()
    ..sort((a, b) {
      final byDate = b.committedDate.compareTo(a.committedDate);
      return byDate != 0 ? byDate : seen[a.sha]!.compareTo(seen[b.sha]!);
    });

  final home = {for (final c in visible) c.sha: inLogs[c.sha]!.reduce((a, b) => a < b ? a : b)};

  // Columns: the base, then each branch with commits of its own, in order.
  final ownCount = List.filled(logs.length, 0);
  for (final lane in home.values) {
    ownCount[lane]++;
  }
  final laneColumn = <int, int>{0: 0};
  for (var i = 1; i < logs.length; i++) {
    if (ownCount[i] > 0) laneColumn[i] = laneColumn.length;
  }

  final rows = [for (final c in visible) GraphRow(GraphNode(c, lane: home[c.sha]!, column: laneColumn[home[c.sha]!]!))];
  final rowOf = {for (final (i, r) in rows.indexed) r.sha: i};

  /// [lower] == rows.length: the line continues past the last loaded row.
  void edge(int upper, int lower, int column, int color, {bool dashed = false}) {
    rows[upper].segments.add(OutSegment(column, color, dashed: dashed));
    for (var r = upper + 1; r < lower && r < rows.length; r++) {
      rows[r].segments.add(PassSegment(column, color, dashed: dashed));
    }
    if (lower < rows.length) rows[lower].segments.add(InSegment(column, color, dashed: dashed));
  }

  // Lane lines: each commit to the next one in the log of the lane it's in.
  final forks = <int, String>{};
  final drawn = <(String, String)>{};
  for (final (li, log) in logs.indexed) {
    final column = laneColumn[li];
    if (column == null) continue;
    for (var i = 0; i < log.commits.length; i++) {
      final c = log.commits[i];
      final from = rowOf[c.sha];
      if (from == null || home[c.sha] != li) continue;
      if (i + 1 >= log.commits.length) {
        // The file's first commit on this branch, unless older pages follow.
        if (!log.complete) edge(from, rows.length, column, li);
        continue;
      }
      final next = log.commits[i + 1];
      if (home[next.sha] != li) forks.putIfAbsent(li, () => next.sha);
      if (!drawn.add((c.sha, next.sha))) continue;
      final to = rowOf[next.sha] ?? rows.length; // hidden: continues below
      if (to > from) edge(from, to, column, li);
    }
  }

  // Dashed links (copies, reverts) get their own columns, reused once free.
  final linkEnds = <int>[]; // lower row of the last link in each link column
  final firstLinkColumn = laneColumn.length;
  void link(int a, int b, int color) {
    final (upper, lower) = a < b ? (a, b) : (b, a);
    var slot = linkEnds.indexWhere((end) => end < upper);
    if (slot < 0) {
      if (linkEnds.length >= maxLinkColumns) return;
      slot = linkEnds.length;
      linkEnds.add(lower);
    } else {
      linkEnds[slot] = lower;
    }
    edge(upper, lower, firstLinkColumn + slot, color, dashed: true);
  }

  final byChange = <(String, String, DateTime), List<GraphNode>>{};
  for (final r in rows) {
    final c = r.node.commit;
    (byChange[(c.title, c.authorName, c.date)] ??= []).add(r.node);
  }
  final copied = List.filled(logs.length, 0);
  for (final same in byChange.values.where((g) => g.length > 1)) {
    // Rows are newest first, so the last one is the original.
    final original = same.last;
    copied[original.lane]++;
    for (final copy in same.take(same.length - 1)) {
      copy
        ..copyOf = original.commit
        ..copyOfLane = original.lane;
      original.copies.add(copy.commit);
      link(rowOf[copy.sha]!, rowOf[original.sha]!, original.lane);
    }
  }

  for (final (i, r) in rows.indexed) {
    final reverted = _revertTitle.firstMatch(r.node.commit.title)?[1];
    if (reverted == null) continue;
    // The closest older commit with that title.
    final target = rows.skip(i + 1).where((o) => o.node.commit.title == reverted).firstOrNull;
    if (target == null) continue;
    r.node.reverts = target.node.commit;
    target.node.revertedBy = r.node.commit;
    link(i, rowOf[target.sha]!, -1);
  }

  for (final log in logs) {
    final tip = log.commits.firstOrNull;
    final row = tip == null ? null : rowOf[tip.sha];
    if (row != null) rows[row].node.tips.add(log.name);
  }

  final lanes = [
    for (final (i, log) in logs.indexed)
      GraphLane(
        index: i,
        name: log.name,
        column: laneColumn[i],
        ownCommits: ownCount[i],
        copiedCommits: copied[i],
        forkSha: forks[i],
      ),
  ];
  return HistoryGraph(lanes: lanes, rows: rows, columns: firstLinkColumn + linkEnds.length, truncated: cutoff != null);
}
