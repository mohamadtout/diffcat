import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';

/// Where a custom button runs.
enum CommandTarget {
  /// The built-in API console (no clone; see docs/commands.md).
  api,

  /// An interactive SSH shell on your own machine (real git / lazygit).
  ssh,
}

class CustomCommand {
  const CustomCommand({required this.id, required this.label, required this.command, required this.target});

  factory CustomCommand.fromJson(Map<String, dynamic> j) => CustomCommand(
    id: j['id'] as String,
    label: j['label'] as String,
    command: j['command'] as String,
    target: CommandTarget.values.byName(j['target'] as String),
  );

  final String id;
  final String label;

  /// API: a console command line. SSH: a key sequence (see key_sequence.dart).
  final String command;
  final CommandTarget target;

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'command': command, 'target': target.name};
}

/// Seeded on first launch; users can edit or delete them.
const defaultCommands = <CustomCommand>[
  CustomCommand(id: 'd-api-log', label: 'Last 20', command: 'log -n 20', target: CommandTarget.api),
  CustomCommand(id: 'd-api-prs', label: 'Open PRs', command: 'prs', target: CommandTarget.api),
  CustomCommand(id: 'd-api-branches', label: 'Branches', command: 'branches', target: CommandTarget.api),
  CustomCommand(
    id: 'd-api-since-tag',
    label: 'Since last tag',
    command: 'since @latest-tag',
    target: CommandTarget.api,
  ),
  CustomCommand(id: 'd-ssh-lazygit', label: 'lazygit', command: 'lazygit<enter>', target: CommandTarget.ssh),
  CustomCommand(id: 'd-ssh-status', label: 'status', command: 'git status -sb<enter>', target: CommandTarget.ssh),
  CustomCommand(
    id: 'd-ssh-fetch',
    label: 'fetch',
    command: 'git fetch --all --prune<enter>',
    target: CommandTarget.ssh,
  ),
  CustomCommand(
    id: 'd-ssh-graph',
    label: 'graph',
    command: 'git log --oneline --graph --decorate -30<enter>',
    target: CommandTarget.ssh,
  ),
  CustomCommand(id: 'd-lg-stage', label: 'LG stage all', command: 'a', target: CommandTarget.ssh),
  CustomCommand(id: 'd-lg-commit', label: 'LG commit', command: 'c', target: CommandTarget.ssh),
  CustomCommand(id: 'd-lg-pull', label: 'LG pull', command: 'p', target: CommandTarget.ssh),
  CustomCommand(id: 'd-lg-push', label: 'LG push', command: 'P', target: CommandTarget.ssh),
  CustomCommand(id: 'd-lg-quit', label: 'LG quit', command: 'q', target: CommandTarget.ssh),
  CustomCommand(id: 'd-ssh-ctrlc', label: '^C', command: '<c-c>', target: CommandTarget.ssh),
];

final customCommandsProvider = NotifierProvider<CustomCommandsNotifier, List<CustomCommand>>(
  CustomCommandsNotifier.new,
);

class CustomCommandsNotifier extends Notifier<List<CustomCommand>> {
  @override
  List<CustomCommand> build() {
    final prefs = ref.watch(sharedPrefsProvider);
    if (!prefs.containsKey(StoreKeys.customCommands)) return defaultCommands;
    return prefs.readJsonList(StoreKeys.customCommands).map(CustomCommand.fromJson).toList();
  }

  Future<void> upsert(CustomCommand c) => _save([
    for (final e in state)
      if (e.id == c.id) c else e,
    if (!state.any((e) => e.id == c.id)) c,
  ]);

  Future<void> remove(String id) => _save(state.where((e) => e.id != id).toList());

  /// [newIndex] is the final position (already adjusted for the removal).
  Future<void> move(int oldIndex, int newIndex) {
    final list = [...state];
    list.insert(newIndex, list.removeAt(oldIndex));
    return _save(list);
  }

  Future<void> resetDefaults() => _save(defaultCommands);

  Future<void> _save(List<CustomCommand> list) async {
    state = list;
    await ref.read(sharedPrefsProvider).writeJsonList(StoreKeys.customCommands, list.map((c) => c.toJson()).toList());
  }
}
