import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/common.dart';
import 'history_graph.dart';

/// Branch colors. Lane 0 (the branch the history was opened on) uses the
/// theme's primary color; the rest cycle through these, which read on both
/// light and dark backgrounds.
const _laneColors = [
  Color(0xFFA371F7), // purple
  Color(0xFF1FB5A1), // teal
  Color(0xFFF0883E), // orange
  Color(0xFFE85AAD), // pink
  Color(0xFF7CB342), // green
  Color(0xFFD4A72C), // amber
];

/// Color of lane [lane]; -1 is the revert link color.
Color laneColor(BuildContext context, int lane) {
  final scheme = Theme.of(context).colorScheme;
  if (lane < 0) return scheme.error;
  if (lane == 0) return scheme.primary;
  return _laneColors[(lane - 1) % _laneColors.length];
}

/// Geometry shared by the painter and the rows it sits in.
abstract final class GraphMetrics {
  static const column = 14.0;
  static const side = 12.0;

  /// Node center from the top of a row, level with the title's first line.
  static const nodeY = 21.0;

  static double width(int columns) => side * 2 + math.max(0, columns - 1) * column;
  static double x(int column) => side + column * GraphMetrics.column;
}

/// Paints one row's slice of the graph: lines passing through, lines into and
/// out of the node, and the node itself.
class GraphRowPainter extends CustomPainter {
  GraphRowPainter({required this.row, required this.colors, required this.background, this.emphasized = false});

  final GraphRow row;
  final Color Function(int lane) colors;

  /// Behind the node, so lines don't run through it.
  final Color background;
  final bool emphasized;

  static const _radius = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final node = row.node;
    final nx = GraphMetrics.x(node.column);
    const ny = GraphMetrics.nodeY;
    final h = size.height;

    for (final s in row.segments) {
      final x = GraphMetrics.x(s.column);
      final dir = (x - nx).sign;
      final r = math.min(_radius, (x - nx).abs());
      final path = Path();
      switch (s) {
        case PassSegment():
          path
            ..moveTo(x, 0)
            ..lineTo(x, h);
        case InSegment():
          path.moveTo(x, 0);
          if (dir == 0) {
            path.lineTo(x, ny);
          } else {
            // Down the column, round the corner, across into the node.
            path
              ..lineTo(x, ny - r)
              ..quadraticBezierTo(x, ny, x - dir * r, ny)
              ..lineTo(nx, ny);
          }
        case OutSegment():
          path.moveTo(nx, ny);
          if (dir == 0) {
            path.lineTo(x, h);
          } else {
            path
              ..lineTo(x - dir * r, ny)
              ..quadraticBezierTo(x, ny, x, ny + r)
              ..lineTo(x, h);
          }
      }
      final paint = Paint()
        ..color = colors(s.color).withValues(alpha: s.dashed ? 0.8 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.dashed ? 1.5 : 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(s.dashed ? _dash(path) : path, paint);
    }

    final color = colors(node.lane);
    final center = Offset(nx, ny);
    if (emphasized) canvas.drawCircle(center, 10, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(center, 7, Paint()..color = background);
    final fill = Paint()..color = color;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (node.copyOf != null) {
      // Rebased or cherry-picked copy: a diamond.
      canvas.drawPath(
        Path()
          ..moveTo(nx, ny - 6)
          ..lineTo(nx + 6, ny)
          ..lineTo(nx, ny + 6)
          ..lineTo(nx - 6, ny)
          ..close(),
        fill,
      );
    } else if (node.commit.isMerge) {
      canvas
        ..drawCircle(center, 4.5, ring)
        ..drawCircle(center, 1.8, fill);
    } else {
      canvas.drawCircle(center, node.tips.isEmpty ? 4.5 : 5.5, fill);
    }
  }

  static Path _dash(Path source, {double on = 4, double off = 3}) {
    final out = Path();
    for (final PathMetric m in source.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += on + off) {
        out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(GraphRowPainter old) =>
      old.row != row || old.background != background || old.emphasized != emphasized;
}

/// One commit: its slice of the graph, then title, badges and meta.
class GraphRowTile extends StatelessWidget {
  const GraphRowTile({
    super.key,
    required this.row,
    required this.graph,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.picked = false,
  });

  final GraphRow row;
  final HistoryGraph graph;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Shown in the detail pane.
  final bool selected;

  /// Picked for comparing two versions.
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final node = row.node;
    final c = node.commit;
    final background = picked
        ? scheme.tertiaryContainer
        : selected
        ? scheme.secondaryContainer
        : theme.scaffoldBackgroundColor;
    final meta = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    String laneName(int? lane) => lane == null ? '' : ' on ${graph.lanes[lane].name}';

    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: CustomPaint(
          painter: GraphRowPainter(
            row: row,
            colors: (lane) => laneColor(context, lane),
            background: background,
            emphasized: selected || picked,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(GraphMetrics.width(graph.columns), 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tip in node.tips)
                      _Tag(
                        icon: Icons.call_split,
                        label: tip,
                        color: laneColor(context, graph.lanes.indexWhere((l) => l.name == tip)),
                      ),
                    if (c.isMerge) _Tag(icon: Icons.merge, label: 'merge', color: scheme.outline),
                    if (node.copyOf case final o?)
                      _Tag(
                        icon: Icons.copy_all,
                        label: 'rebased from ${o.shortSha}${laneName(node.copyOfLane)}',
                        color: laneColor(context, node.copyOfLane ?? 0),
                      ),
                    if (node.copies.isNotEmpty)
                      _Tag(
                        icon: Icons.copy_all,
                        label: 'copied as ${node.copies.map((c) => c.shortSha).join(', ')}',
                        color: scheme.outline,
                      ),
                    if (node.reverts case final r?)
                      _Tag(icon: Icons.undo, label: 'reverts ${r.shortSha}', color: scheme.error),
                    if (node.revertedBy case final r?)
                      _Tag(icon: Icons.undo, label: 'reverted by ${r.shortSha}', color: scheme.error),
                    Text('${c.authorLogin ?? c.authorName} · ${relativeTime(c.committedDate)}', style: meta),
                    ShaChip(c.sha),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color, fontFamily: AppTheme.monoFamily),
          ),
        ),
      ],
    ),
  );
}

/// The branches in the graph with their colors and what they did to the file.
class GraphLegend extends StatelessWidget {
  const GraphLegend({super.key, required this.graph, required this.errors, this.onAdd});

  final HistoryGraph graph;

  /// Branches that failed to load, by name.
  final Map<String, Object> errors;
  final VoidCallback? onAdd;

  String _status(GraphLane lane) {
    if (errors.containsKey(lane.name)) return "couldn't load";
    final base = graph.lanes.first.name;
    if (lane.isBase) return '${lane.ownCommits} change${lane.ownCommits == 1 ? '' : 's'}';
    if (lane.ownCommits == 0) {
      return graph.rows.any((r) => r.node.tips.contains(lane.name)) ? 'nothing beyond $base' : 'no history';
    }
    final landed = lane.copiedCommits == lane.ownCommits
        ? ' · rebased into $base'
        : lane.copiedCommits > 0
        ? ' · ${lane.copiedCommits} rebased'
        : '';
    return '${lane.ownCommits} not on $base$landed';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final lane in graph.lanes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      errors.containsKey(lane.name) ? Icons.error_outline : Icons.circle,
                      size: 10,
                      color: errors.containsKey(lane.name) ? theme.colorScheme.error : laneColor(context, lane.index),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lane.name, style: theme.textTheme.labelMedium?.copyWith(fontFamily: AppTheme.monoFamily)),
                        Text(
                          _status(lane),
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (onAdd != null)
            ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Branches'), onPressed: onAdd),
        ],
      ),
    );
  }
}
