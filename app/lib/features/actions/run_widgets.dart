import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/relative_time.dart';
import '../../data/github/models/models.dart';

/// GitHub's "attention" yellow, for runs that are still going.
const _pending = Color(0xFFBF8700);

/// Status of a run, job or step, in GitHub's colors.
class RunStateIcon extends StatelessWidget {
  const RunStateIcon(this.state, {super.key, this.size = 24});

  final RunState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = DiffColors.of(context);
    final muted = Theme.of(context).colorScheme.outline;
    final (icon, color) = switch (state) {
      RunState.queued || RunState.waiting => (Icons.schedule, _pending),
      RunState.inProgress => (Icons.timelapse, _pending),
      RunState.success => (Icons.check_circle, c.addFg),
      RunState.failure => (Icons.cancel, c.delFg),
      RunState.cancelled => (Icons.block, muted),
      RunState.skipped => (Icons.skip_next_outlined, muted),
      RunState.neutral => (Icons.remove_circle_outline, muted),
      RunState.actionRequired => (Icons.error_outline, _pending),
    };
    return Semantics(
      label: state.label,
      child: Icon(icon, color: color, size: size),
    );
  }
}

/// "Push", "Pull request", "Manual"…: what started a run.
String eventLabel(String event) => switch (event) {
  'push' => 'Push',
  'pull_request' || 'pull_request_target' => 'Pull request',
  'workflow_dispatch' => 'Manual',
  'schedule' => 'Scheduled',
  'release' => 'Release',
  'merge_group' => 'Merge queue',
  'workflow_run' => 'After a workflow',
  'repository_dispatch' => 'API',
  'dynamic' => 'GitHub',
  _ => event.replaceAll('_', ' '),
};

class RunTile extends StatelessWidget {
  const RunTile({super.key, required this.run, required this.onTap, this.selected = false});

  final GhWorkflowRun run;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    leading: RunStateIcon(run.state),
    title: Text(run.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        '${run.workflowName} #${run.runNumber}',
        ?run.headBranch,
        eventLabel(run.event),
        relativeTime(run.createdAt),
        if (run.state != RunState.queued) shortDuration(run.duration()),
      ].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: onTap,
  );
}

/// Calls [onRefresh] every [every] while [active], but only when it can be
/// seen: not on a hidden repo tab, a covered route, or with the app in the
/// background. Each tick is a request, so nothing polls out of sight.
class AutoRefresh extends StatefulWidget {
  const AutoRefresh({
    super.key,
    required this.active,
    required this.onRefresh,
    required this.child,
    this.every = const Duration(seconds: 15),
  });

  final bool active;
  final VoidCallback onRefresh;
  final Duration every;
  final Widget child;

  @override
  State<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends State<AutoRefresh> {
  Timer? _timer;
  var _visible = true;

  @override
  void didUpdateWidget(AutoRefresh old) {
    super.didUpdateWidget(old);
    if (old.every != widget.every) _stop();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (!mounted || !_visible || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    widget.onRefresh();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _visible = Visibility.of(context) && TickerMode.valuesOf(context).enabled;
    if (widget.active) {
      _timer ??= Timer.periodic(widget.every, (_) => _tick());
    } else {
      _stop();
    }
    return widget.child;
  }
}
