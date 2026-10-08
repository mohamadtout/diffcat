import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../commits/commits_providers.dart';
import '../repo/repo_providers.dart';

typedef _HeadKey = ({RepoRef repo, String ref});

/// The last 100 commits on a ref — the choices for "since commit…".
final _recentCommitsProvider = FutureProvider.autoDispose.family<List<GhCommit>, _HeadKey>(
  (ref, k) async => (await ref.watch(githubApiProvider).commits(k.repo, ref: k.ref, perPage: 100)).items,
);

/// "Which files changed since commit X?" — pick X from a dropdown (recent
/// commits, tags, branches or a typed SHA) and get the file list.
class ChangedSinceScreen extends ConsumerStatefulWidget {
  const ChangedSinceScreen({super.key, required this.repo, this.initialHead, this.initialBase});

  final RepoRef repo;
  final String? initialHead;
  final String? initialBase;

  @override
  ConsumerState<ChangedSinceScreen> createState() => _ChangedSinceScreenState();
}

class _ChangedSinceScreenState extends ConsumerState<ChangedSinceScreen> {
  String? _head;
  String? _base;
  final _baseCtrl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _head = widget.initialHead;
    _base = widget.initialBase;
    if (_base != null) _baseCtrl.text = _base!.length == 40 ? _base!.substring(0, 7) : _base!;
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(repoProvider(widget.repo));
    return Scaffold(
      appBar: AppBar(title: const Text('Changed since…')),
      body: AsyncView(
        value: repoAsync,
        onRetry: () => ref.invalidate(repoProvider(widget.repo)),
        data: (repo) {
          final head = _head ?? repo.defaultBranch;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [_headPicker(head), _basePicker(head)],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: _base == null
                    ? const EmptyView(
                        icon: Icons.difference_outlined,
                        message: 'Pick a starting commit to list every file changed since then.',
                      )
                    : _result(head, _base!),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _headPicker(String head) {
    final branches = ref.watch(branchesProvider(widget.repo)).value ?? const <GhBranch>[];
    final names = {head, ...branches.map((b) => b.name)}.toList();
    return DropdownMenu<String>(
      key: ValueKey('head-$head-${names.length}'),
      label: const Text('Up to (head)'),
      leadingIcon: const Icon(Icons.call_split),
      initialSelection: head,
      width: math.min(260, MediaQuery.sizeOf(context).width - 32),
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 360,
      dropdownMenuEntries: [for (final n in names) DropdownMenuEntry(value: n, label: n)],
      onSelected: (v) => setState(() => _head = v),
    );
  }

  Widget _basePicker(String head) {
    final commits = ref.watch(_recentCommitsProvider((repo: widget.repo, ref: head)));
    final tags = ref.watch(tagsProvider(widget.repo)).value ?? const <GhBranch>[];
    final entries = <DropdownMenuEntry<String>>[
      for (final c in commits.value ?? const <GhCommit>[])
        DropdownMenuEntry(
          value: c.sha,
          label: '${c.shortSha}  ${c.title}',
          labelWidget: _CommitEntry(commit: c),
        ),
      for (final t in tags)
        DropdownMenuEntry(value: t.sha, label: 'tag ${t.name}', leadingIcon: const Icon(Icons.sell_outlined, size: 18)),
    ];
    void applyTyped() {
      FocusScope.of(context).unfocus();
      final text = _baseCtrl.text.trim();
      if (text.isEmpty) return;
      // Typed text may be an entry's label (after picking) or a raw SHA / tag.
      final match = entries.where((e) => e.label == text).firstOrNull;
      final value = match?.value ?? (text.startsWith('tag ') ? text.substring(4) : text.split(RegExp(r'\s+')).first);
      setState(() => _base = value);
    }

    final dropdown = DropdownMenu<String>(
      controller: _baseCtrl,
      label: const Text('Since commit (exclusive)'),
      leadingIcon: const Icon(Icons.commit),
      helperText: commits.isLoading ? 'Loading commits…' : 'Pick one, or type a SHA / tag and tap →',
      // Fit phones: screen minus page padding (32) and the → button (56).
      width: math.min(360, MediaQuery.sizeOf(context).width - 88),
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      menuHeight: 420,
      dropdownMenuEntries: entries,
      onSelected: (v) {
        FocusScope.of(context).unfocus();
        if (v != null) setState(() => _base = v);
      },
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        dropdown,
        const SizedBox(width: 4),
        IconButton.filledTonal(
          tooltip: 'Use typed SHA / tag',
          icon: const Icon(Icons.arrow_forward),
          onPressed: applyTyped,
        ),
      ],
    );
  }

  Widget _result(String head, String base) {
    final key = (repo: widget.repo, base: base, head: head);
    return AsyncView(
      value: ref.watch(compareProvider(key)),
      onRetry: () => ref.invalidate(compareProvider(key)),
      data: (cmp) {
        final files = [...cmp.files]..sort((a, b) => a.filename.compareTo(b.filename));
        final shown = _filter.isEmpty ? files : files.where((f) => f.filename.toLowerCase().contains(_filter)).toList();
        final adds = files.fold<int>(0, (s, f) => s + f.additions);
        final dels = files.fold<int>(0, (s, f) => s + f.deletions);
        final theme = Theme.of(context);
        return ListView.builder(
          itemCount: shown.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${files.length} files · ${cmp.totalCommits} commits',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        LineCounts(additions: adds, deletions: dels),
                      ],
                    ),
                    if (cmp.status == 'diverged' || cmp.status == 'behind')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Note: base is not an ancestor of head (${cmp.status}); '
                          'showing changes since their merge base.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (cmp.filesTruncated)
                      Text('GitHub returns at most 300 files for a comparison.', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.filter_list),
                              hintText: 'Filter paths',
                            ),
                            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.difference),
                          label: const Text('Review diffs'),
                          onPressed: files.isEmpty ? null : () => context.push(Routes.compare(widget.repo, base, head)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
            final f = shown[i - 1];
            return ListTile(
              dense: true,
              leading: StatusBadge(f.status),
              title: Text(f.basename, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                f.previousFilename != null ? '${f.previousFilename} → ${f.filename}' : f.filename,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: LineCounts(additions: f.additions, deletions: f.deletions),
              onTap: () => context.push(Routes.compare(widget.repo, base, head, file: f.filename)),
              onLongPress: () => context.push(Routes.history(widget.repo, f.filename, head)),
            );
          },
        );
      },
    );
  }
}

class _CommitEntry extends StatelessWidget {
  const _CommitEntry({required this.commit});
  final GhCommit commit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Row(
      children: [
        ShaChip(commit.sha),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(commit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${commit.authorLogin ?? commit.authorName} · ${relativeTime(commit.date)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
