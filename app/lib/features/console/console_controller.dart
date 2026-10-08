import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import 'command_executor.dart';
import 'console_models.dart';

/// Per-repo console scrollback. Kept alive (not autoDispose) so output
/// survives switching tabs or leaving the repo.
final consoleProvider = NotifierProvider.family<ConsoleController, List<ConsoleEntry>, RepoRef>(ConsoleController.new);

class ConsoleController extends Notifier<List<ConsoleEntry>> {
  ConsoleController(this.repo);
  final RepoRef repo;

  static const _maxEntries = 100;
  final List<String> history = [];

  @override
  List<ConsoleEntry> build() => const [];

  void clear() => state = const [];

  /// Runs [input]. Returns a route if the command is a navigation (`open`).
  Future<String?> run(String input, {required String gitRef}) async {
    final line = input.trim();
    if (line.isEmpty) return null;
    if (history.isEmpty || history.last != line) history.add(line);
    if (line == 'clear') {
      clear();
      return null;
    }
    final exec = CommandExecutor(api: ref.read(githubApiProvider), repo: repo, ref: gitRef);

    try {
      final route = exec.routeFor(line);
      if (route != null) return route;
    } on ConsoleUsageError catch (e) {
      _append(ConsoleEntry(input: line, output: [ConsoleLine.text(e.message, SpanStyle.error)]));
      return null;
    }

    final index = state.length;
    _append(ConsoleEntry(input: line, running: true));
    List<ConsoleLine> output;
    try {
      output = await exec.run(line);
    } catch (e) {
      output = [ConsoleLine.text(e.toString(), SpanStyle.error)];
    }
    if (!ref.mounted) return null;
    final list = [...state];
    // Entries may have been trimmed or cleared while the command ran.
    final i = list.length > index && list[index].input == line && list[index].running
        ? index
        : list.lastIndexWhere((e) => e.running && e.input == line);
    if (i >= 0) {
      list[i] = ConsoleEntry(input: line, output: output);
      state = list;
    }
    return null;
  }

  void _append(ConsoleEntry e) {
    final list = [...state, e];
    state = list.length > _maxEntries ? list.sublist(list.length - _maxEntries) : list;
  }
}
