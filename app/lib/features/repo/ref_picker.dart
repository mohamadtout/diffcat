import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import 'repo_providers.dart';

/// App-bar button showing the current branch; opens a searchable picker of
/// branches and tags.
class RefPickerButton extends StatelessWidget {
  const RefPickerButton({super.key, required this.repo, required this.current, required this.onSelected});

  final RepoRef repo;
  final String current;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = RegExp(r'^[0-9a-f]{40}$').hasMatch(current) ? current.substring(0, 7) : current;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: TextButton.icon(
        icon: const Icon(Icons.call_split, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
        onPressed: () async {
          final picked = await showModalBottomSheet<String>(
            context: context,
            useRootNavigator: true, // cover the shell navigation bar/rail
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _RefSheet(repo: repo, current: current),
          );
          if (picked != null) onSelected(picked);
        },
      ),
    );
  }
}

class _RefSheet extends ConsumerStatefulWidget {
  const _RefSheet({required this.repo, required this.current});
  final RepoRef repo;
  final String current;

  @override
  ConsumerState<_RefSheet> createState() => _RefSheetState();
}

class _RefSheetState extends ConsumerState<_RefSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider(widget.repo));
    final tags = ref.watch(tagsProvider(widget.repo));
    final items = <(String, bool)>[
      for (final b in branches.value ?? const <GhBranch>[]) (b.name, false),
      for (final t in tags.value ?? const <GhBranch>[]) (t.name, true),
    ].where((e) => e.$1.toLowerCase().contains(_q)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Branch or tag'),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          if (branches.isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final (name, isTag) = items[i];
                return ListTile(
                  dense: true,
                  leading: Icon(isTag ? Icons.sell_outlined : Icons.call_split),
                  title: Text(name),
                  selected: name == widget.current,
                  onTap: () => Navigator.pop(context, name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
