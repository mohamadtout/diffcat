import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import 'actions_providers.dart';
import 'job_log.dart';
import 'run_widgets.dart';

/// One job's log, with steps' setup folded away as on github.com and a
/// button that steps through the errors.
class JobLogScreen extends ConsumerWidget {
  const JobLogScreen({super.key, required this.repo, required this.jobId});

  final RepoRef repo;
  final int jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (repo: repo, id: jobId);
    final job = ref.watch(jobProvider(key));
    final j = job.hasValue ? job.requireValue : null;
    final running = j?.state.isActive ?? false;
    return AutoRefresh(
      // GitHub has the log once the job is done; until then, watch for that.
      active: running && ref.watch(isSignedInProvider),
      every: const Duration(seconds: 10),
      onRefresh: () => ref.invalidate(jobProvider(key)),
      child: j != null && !running
          ? _LogView(jobKey: key, job: j)
          : Scaffold(
              appBar: AppBar(title: Text(j?.name ?? 'Job log')),
              body: j == null
                  ? AsyncView(
                      value: job,
                      onRetry: () => ref.invalidate(jobProvider(key)),
                      data: (_) => const SizedBox(),
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(jobProvider(key).future),
                      child: LayoutBuilder(
                        builder: (context, c) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: c.maxHeight,
                            child: const EmptyView(
                              icon: Icons.timelapse,
                              message: 'This job is still running. Its log is available here once it finishes.',
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
    );
  }
}

class _LogView extends ConsumerStatefulWidget {
  const _LogView({required this.jobKey, required this.job});

  final JobKey jobKey;
  final GhJob job;

  @override
  ConsumerState<_LogView> createState() => _LogViewState();
}

class _LogViewState extends ConsumerState<_LogView> {
  final _expanded = <int>{};
  final _scroll = ScrollController();
  final _list = ListController();

  /// The error the last "Next error" jumped to.
  int _error = -1;

  @override
  void dispose() {
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  void _nextError(List<LogLine> lines) {
    final errors = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].kind == LogKind.error) i,
    ];
    if (errors.isEmpty) return;
    final target = errors.firstWhere((i) => i > _error, orElse: () => errors.first);
    setState(() {
      _error = target;
      if (lines[target].group case final g?) _expanded.add(g);
    });
    final at = visibleLogLines(lines, _expanded).indexOf(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && at >= 0) _list.jumpToItem(index: at, scrollController: _scroll, alignment: 0.3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(jobLogProvider(widget.jobKey));
    final lines = log.value;
    final errorCount = lines?.where((l) => l.kind == LogKind.error).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.job.name, overflow: TextOverflow.ellipsis),
            Text(widget.job.state.label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        actions: [
          if (errorCount > 0)
            IconButton(
              tooltip: 'Next error ($errorCount)',
              icon: const Icon(Icons.error_outline),
              onPressed: () => _nextError(lines!),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  Clipboard.setData(ClipboardData(text: lines!.map((l) => l.text).join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log copied')));
                case 'web':
                  launchUrl(Uri.parse(widget.job.htmlUrl!), mode: LaunchMode.externalApplication);
              }
            },
            itemBuilder: (_) => [
              if (lines != null)
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(leading: Icon(Icons.copy), title: Text('Copy log')),
                ),
              if (widget.job.htmlUrl != null)
                const PopupMenuItem(
                  value: 'web',
                  child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Open on GitHub')),
                ),
            ],
          ),
        ],
      ),
      body: AsyncView(
        value: log,
        onRetry: () => ref.invalidate(jobLogProvider(widget.jobKey)),
        error: (e) => !ref.watch(isSignedInProvider) && e is GitHubException && (e.statusCode ?? 0) ~/ 100 == 4
            ? const EmptyView(icon: Icons.lock_outline, message: 'GitHub shows job logs only when you sign in.')
            : ErrorView(error: e, onRetry: () => ref.invalidate(jobLogProvider(widget.jobKey))),
        data: (lines) =>
            lines.isEmpty ? const EmptyView(icon: Icons.article_outlined, message: 'The log is empty.') : _lines(lines),
      ),
    );
  }

  Widget _lines(List<LogLine> lines) {
    final visible = visibleLogLines(lines, _expanded);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 12, height: 1.35);
    final c = DiffColors.of(context);
    return Scrollbar(
      controller: _scroll,
      interactive: true,
      child: SuperListView.builder(
        controller: _scroll,
        listController: _list,
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final index = visible[i];
          final line = lines[index];
          final (Color? bg, Color? fg) = switch (line.kind) {
            LogKind.error => (c.delBg, c.delFg),
            LogKind.warning => (const Color(0x33BF8700), null),
            LogKind.command => (null, scheme.primary),
            LogKind.debug => (null, scheme.outline),
            LogKind.notice => (null, scheme.tertiary),
            _ => (null, null),
          };
          final group = line.kind == LogKind.group;
          final open = _expanded.contains(index);
          final row = Container(
            color: index == _error ? scheme.secondaryContainer : bg,
            padding: EdgeInsetsDirectional.only(start: line.group == null ? 8 : 24, end: 8, top: 1, bottom: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.end,
                    style: mono.copyWith(color: scheme.outline),
                  ),
                ),
                const SizedBox(width: 8),
                if (group)
                  Icon(open ? Icons.expand_more : Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                Expanded(
                  child: Text(
                    line.text,
                    style: mono.copyWith(color: fg, fontWeight: group ? FontWeight.bold : null),
                  ),
                ),
              ],
            ),
          );
          return group
              ? InkWell(onTap: () => setState(() => open ? _expanded.remove(index) : _expanded.add(index)), child: row)
              : row;
        },
      ),
    );
  }
}
