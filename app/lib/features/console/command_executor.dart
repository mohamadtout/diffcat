import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../data/github/github_api.dart';
import '../../data/github/models/models.dart';
import '../diff/diff_parser.dart';
import '../files/tree_builder.dart';
import 'command_line.dart';
import 'console_models.dart';

/// Runs git-like commands against the GitHub API — nothing is cloned.
///
/// The command reference lives in docs/commands.md; keep [helpText] and that
/// file in sync when adding commands.
class CommandExecutor {
  CommandExecutor({required this.api, required this.repo, required this.ref});

  final GitHubApi api;
  final RepoRef repo;

  /// The ref selected in the repo screen; what `HEAD` means here.
  final String ref;

  static const helpText = <(String, String)>[
    ('log [ref] [-n N] [-- path]', 'Commit history (of a file with -- path)'),
    ('history <path> [-n N]', 'Commits that touched a file'),
    ('show <sha> [--patch|--name-only]', 'Commit summary + changed files'),
    ('diff <a>..<b> [--patch|--stat]', 'Compare two refs (also a...b or a b)'),
    ('since <ref> [head]', 'Files changed since a commit/tag'),
    ('ls [path] [--ref R]', 'List a directory'),
    ('cat <path> [--ref R]', 'Print a file'),
    ('branches | tags', 'List branches / tags'),
    ('prs [--state open|closed|all]', 'List pull requests'),
    ('pr <number>', 'Pull request summary + files'),
    ('open <sha|#pr|path>', 'Open in the visual viewer'),
    ('rate', 'Show remaining GitHub API quota'),
    ('clear', 'Clear the console'),
  ];

  Future<List<ConsoleLine>> run(String line) async {
    final cmd = parseCommand(line);
    return switch (cmd.name) {
      'help' || '?' => _help(),
      'log' => _log(cmd),
      'history' => _history(cmd),
      'show' => _show(cmd),
      'diff' => _diff(cmd),
      'since' || 'changed-since' => _since(cmd),
      'ls' => _ls(cmd),
      'cat' => _cat(cmd),
      'branches' || 'branch' => _branches(),
      'tags' || 'tag' => _tags(),
      'prs' => _prs(cmd),
      'pr' => _pr(cmd),
      'rate' => _rate(),
      _ => throw ConsoleUsageError("Unknown command '${cmd.name}'. Type 'help'."),
    };
  }

  /// Parses `open …` without hitting the network. Returns null if not a
  /// navigation command.
  String? routeFor(String line) {
    final cmd = parseCommand(line);
    if (cmd.name != 'open') return null;
    final target = cmd.positional(0);
    if (target == null) throw ConsoleUsageError('usage: open <sha|#pr|path>');
    if (target.startsWith('#')) {
      final n = int.tryParse(target.substring(1));
      if (n == null) throw ConsoleUsageError('Bad PR number: $target');
      return Routes.pull(repo, n);
    }
    if (RegExp(r'^[0-9a-f]{7,40}$').hasMatch(target)) return Routes.commit(repo, target);
    return Routes.file(repo, target, cmd.opt('ref') ?? ref);
  }

  // ---------------------------------------------------------------- commands

  List<ConsoleLine> _help() => [
    ConsoleLine.text('Commands run against the GitHub API (no clone). "git " prefix optional.', SpanStyle.dim),
    for (final (usage, desc) in helpText)
      ConsoleLine([ConsoleSpan(usage.padRight(34), SpanStyle.accent), ConsoleSpan(desc, SpanStyle.dim)]),
    ConsoleLine.text('Refs: branch, tag, sha, HEAD, HEAD~N, @latest-tag', SpanStyle.dim),
    ConsoleLine.text('Tap a line with a sha/file to open it.', SpanStyle.dim),
  ];

  Future<List<ConsoleLine>> _log(ParsedCommand c) async {
    final at = await _resolve(c.positional(0) ?? 'HEAD');
    final n = c.intOpt('n', 20).clamp(1, 100);
    final path = c.paths.isEmpty ? null : c.paths.first;
    final page = await api.commits(repo, ref: at, path: path, perPage: n);
    if (page.items.isEmpty) return [ConsoleLine.text('(no commits)', SpanStyle.dim)];
    return [
      for (final commit in page.items) _commitLine(commit, focusPath: path),
      if (page.hasNext) ConsoleLine.text('… more (use -n up to 100)', SpanStyle.dim),
    ];
  }

  Future<List<ConsoleLine>> _history(ParsedCommand c) {
    final path = c.positional(0);
    if (path == null) throw ConsoleUsageError('usage: history <path>');
    return _log(ParsedCommand('log', const [], c.options, [path]));
  }

  Future<List<ConsoleLine>> _show(ParsedCommand c) async {
    final sha = await _resolve(c.positional(0) ?? 'HEAD');
    final commit = await api.commit(repo, sha);
    return [
      ConsoleLine([
        const ConsoleSpan('commit ', SpanStyle.heading),
        ConsoleSpan(commit.sha, SpanStyle.sha),
      ], route: Routes.commit(repo, commit.sha)),
      ConsoleLine.text(
        'Author: ${commit.authorName}${commit.authorLogin == null ? '' : ' (@${commit.authorLogin})'}',
        SpanStyle.dim,
      ),
      ConsoleLine.text('Date:   ${fullTimestamp(commit.date)}', SpanStyle.dim),
      if (commit.isMerge)
        ConsoleLine.text('Merge:  ${commit.parents.map((p) => p.substring(0, 7)).join(' ')}', SpanStyle.dim),
      const ConsoleLine([]),
      for (final l in commit.message.trimRight().split('\n')) ConsoleLine.text('    $l'),
      const ConsoleLine([]),
      ..._files(commit.files, c, (f) => Routes.commit(repo, commit.sha, file: f)),
    ];
  }

  Future<List<ConsoleLine>> _diff(ParsedCommand c) async {
    String? a, b;
    final first = c.positional(0);
    if (first == null) throw ConsoleUsageError('usage: diff <base>..<head>');
    final range = RegExp(r'^(.*?)\.{2,3}(.*)$').firstMatch(first);
    if (range != null) {
      a = range.group(1)!.isEmpty ? 'HEAD' : range.group(1);
      b = range.group(2)!.isEmpty ? 'HEAD' : range.group(2);
    } else {
      a = first;
      b = c.positional(1) ?? 'HEAD';
    }
    return _compareLines(await _resolve(a!), await _resolve(b!), c);
  }

  Future<List<ConsoleLine>> _since(ParsedCommand c) async {
    final base = c.positional(0);
    if (base == null) throw ConsoleUsageError('usage: since <commit|tag> [head]');
    return _compareLines(await _resolve(base), await _resolve(c.positional(1) ?? 'HEAD'), c);
  }

  Future<List<ConsoleLine>> _compareLines(String base, String head, ParsedCommand c) async {
    final cmp = await api.compare(repo, base, head);
    return [
      ConsoleLine([
        ConsoleSpan('${_short(base)}...${_short(head)}', SpanStyle.heading),
        ConsoleSpan('  ${cmp.totalCommits} commits, ${cmp.files.length} files (${cmp.status})', SpanStyle.dim),
      ], route: Routes.compare(repo, base, head)),
      if (cmp.filesTruncated) ConsoleLine.text('GitHub caps comparisons at 300 files.', SpanStyle.dim),
      ..._files(cmp.files, c, (f) => Routes.compare(repo, base, head, file: f)),
    ];
  }

  Future<List<ConsoleLine>> _ls(ParsedCommand c) async {
    final at = await _resolve(c.opt('ref') ?? 'HEAD');
    final path = (c.positional(0) ?? '').replaceAll(RegExp(r'^/+|/+$'), '');
    final root = buildTree((await api.tree(repo, at)).entries);
    var node = root;
    if (path.isNotEmpty) {
      for (final part in path.split('/')) {
        final next = node.children.where((n) => n.name == part).firstOrNull;
        if (next == null || !next.isDir) throw ConsoleUsageError('No such directory: $path');
        node = next;
      }
    }
    return [
      for (final n in node.children)
        n.isDir
            ? ConsoleLine.text('${n.name}/', SpanStyle.accent)
            : ConsoleLine([
                ConsoleSpan(n.name),
                if (n.size != null) ConsoleSpan('  ${n.size} B', SpanStyle.dim),
              ], route: Routes.file(repo, n.path, at)),
    ];
  }

  Future<List<ConsoleLine>> _cat(ParsedCommand c) async {
    final path = c.positional(0);
    if (path == null) throw ConsoleUsageError('usage: cat <path> [--ref R]');
    final at = await _resolve(c.opt('ref') ?? 'HEAD');
    final content = await api.fileContent(repo, path, at);
    if (content.contains('\u0000')) return [ConsoleLine.text('(binary file)', SpanStyle.dim)];
    const max = 400;
    final lines = content.split('\n');
    return [
      for (final l in lines.take(max)) ConsoleLine.text(l),
      if (lines.length > max)
        ConsoleLine.text(
          '… ${lines.length - max} more lines — tap to open viewer',
          SpanStyle.dim,
          Routes.file(repo, path, at),
        ),
    ];
  }

  Future<List<ConsoleLine>> _branches() async {
    final branches = await api.branches(repo);
    return [
      for (final b in branches)
        ConsoleLine([
          ConsoleSpan(b.name == ref ? '* ' : '  ', SpanStyle.add),
          ConsoleSpan(b.name, b.name == ref ? SpanStyle.add : SpanStyle.normal),
          ConsoleSpan('  ${_short(b.sha)}', SpanStyle.dim),
        ], route: Routes.repo(repo, tab: 'commits', ref: b.name)),
    ];
  }

  Future<List<ConsoleLine>> _tags() async {
    final tags = await api.tags(repo);
    if (tags.isEmpty) return [ConsoleLine.text('(no tags)', SpanStyle.dim)];
    return [
      for (final t in tags)
        ConsoleLine([
          ConsoleSpan(t.name, SpanStyle.accent),
          ConsoleSpan('  ${_short(t.sha)}', SpanStyle.dim),
        ], route: Routes.commit(repo, t.sha)),
    ];
  }

  Future<List<ConsoleLine>> _prs(ParsedCommand c) async {
    final state = c.opt('state') ?? 'open';
    if (!{'open', 'closed', 'all'}.contains(state)) throw ConsoleUsageError('--state must be open, closed or all');
    final page = await api.pulls(repo, state: state);
    if (page.items.isEmpty) return [ConsoleLine.text('(no $state pull requests)', SpanStyle.dim)];
    return [
      for (final p in page.items)
        ConsoleLine([
          ConsoleSpan('#${p.number}'.padRight(7), SpanStyle.accent),
          ConsoleSpan(p.title),
          ConsoleSpan('  ${p.author.login} · ${p.headRef}→${p.baseRef} · ${p.state.name}', SpanStyle.dim),
        ], route: Routes.pull(repo, p.number)),
    ];
  }

  Future<List<ConsoleLine>> _pr(ParsedCommand c) async {
    final n = int.tryParse((c.positional(0) ?? '').replaceFirst('#', ''));
    if (n == null) throw ConsoleUsageError('usage: pr <number>');
    final pull = await api.pull(repo, n);
    final files = await api.pullFiles(repo, n);
    return [
      ConsoleLine([
        ConsoleSpan('#$n ', SpanStyle.accent),
        ConsoleSpan(pull.title, SpanStyle.heading),
      ], route: Routes.pull(repo, n)),
      ConsoleLine.text('${pull.author.login} · ${pull.headRef} → ${pull.baseRef} · ${pull.state.name}', SpanStyle.dim),
      const ConsoleLine([]),
      ..._files(files, c, (_) => Routes.pull(repo, n)),
    ];
  }

  Future<List<ConsoleLine>> _rate() async {
    await api.viewer(); // refreshes the counters
    final client = api.client;
    return [
      ConsoleLine.text('Remaining: ${client.rateLimitRemaining ?? '?'}'),
      if (client.rateLimitReset != null)
        ConsoleLine.text('Resets: ${fullTimestamp(client.rateLimitReset!)}', SpanStyle.dim),
    ];
  }

  // ---------------------------------------------------------------- helpers

  ConsoleLine _commitLine(GhCommit c, {String? focusPath}) => ConsoleLine([
    ConsoleSpan(c.shortSha, SpanStyle.sha),
    ConsoleSpan(' ${c.title}'),
    ConsoleSpan('  ${c.authorLogin ?? c.authorName}, ${relativeTime(c.date)}', SpanStyle.dim),
  ], route: Routes.commit(repo, c.sha, file: focusPath));

  /// Renders a file list as name-status (default), name-only, stat or patch.
  List<ConsoleLine> _files(List<GhFileChange> files, ParsedCommand c, String Function(String file) route) {
    if (files.isEmpty) return [ConsoleLine.text('(no file changes)', SpanStyle.dim)];
    final out = <ConsoleLine>[];
    final adds = files.fold<int>(0, (s, f) => s + f.additions);
    final dels = files.fold<int>(0, (s, f) => s + f.deletions);
    for (final f in files) {
      final name = f.previousFilename == null ? f.filename : '${f.previousFilename} → ${f.filename}';
      if (c.flag('name-only')) {
        out.add(ConsoleLine.text(f.filename, SpanStyle.normal, route(f.filename)));
      } else if (c.flag('stat')) {
        out.add(
          ConsoleLine([
            ConsoleSpan(' $name '),
            ConsoleSpan('+${f.additions}', SpanStyle.add),
            const ConsoleSpan(' '),
            ConsoleSpan('-${f.deletions}', SpanStyle.del),
          ], route: route(f.filename)),
        );
      } else {
        final style = switch (f.status) {
          FileChangeStatus.added => SpanStyle.add,
          FileChangeStatus.removed => SpanStyle.del,
          _ => SpanStyle.accent,
        };
        out.add(ConsoleLine([ConsoleSpan('${f.status.letter}  ', style), ConsoleSpan(name)], route: route(f.filename)));
      }
      if (c.flag('patch') || c.flag('p')) {
        if (f.patch == null) {
          out.add(ConsoleLine.text('    (no inline patch)', SpanStyle.dim));
          continue;
        }
        for (final h in parsePatch(f.patch!)) {
          out.add(ConsoleLine.text(h.header, SpanStyle.accent));
          for (final l in h.lines) {
            out.add(switch (l.kind) {
              DiffLineKind.add => ConsoleLine.text('+${l.text}', SpanStyle.add),
              DiffLineKind.delete => ConsoleLine.text('-${l.text}', SpanStyle.del),
              DiffLineKind.noNewline => ConsoleLine.text('\\ ${l.text}', SpanStyle.dim),
              DiffLineKind.context => ConsoleLine.text(' ${l.text}'),
            });
          }
        }
      }
    }
    out.add(
      ConsoleLine([
        ConsoleSpan(' ${files.length} files changed, ', SpanStyle.dim),
        ConsoleSpan('$adds insertions(+)', SpanStyle.add),
        const ConsoleSpan(', ', SpanStyle.dim),
        ConsoleSpan('$dels deletions(-)', SpanStyle.del),
      ]),
    );
    return out;
  }

  /// Resolves `HEAD`, `HEAD~N`, `<ref>~N` and `@latest-tag` to something GitHub
  /// accepts. `~N` follows GitHub's commit listing order, which matches
  /// first-parent history for linear branches.
  Future<String> _resolve(String spec) async {
    if (spec == 'HEAD' || spec == '@') return ref;
    if (spec == '@latest-tag') {
      final tags = await api.tags(repo);
      if (tags.isEmpty) throw ConsoleUsageError('Repository has no tags');
      return tags.first.sha;
    }
    final m = RegExp(r'^(.+?)~(\d*)$').firstMatch(spec);
    if (m != null) {
      final base = await _resolve(m.group(1)!);
      final n = m.group(2)!.isEmpty ? 1 : int.parse(m.group(2)!);
      if (n == 0) return base;
      if (n > 99) throw ConsoleUsageError('~N supports N ≤ 99');
      final page = await api.commits(repo, ref: base, perPage: n + 1);
      if (page.items.length <= n) throw ConsoleUsageError('$spec: not enough history');
      return page.items[n].sha;
    }
    return spec;
  }

  String _short(String s) => RegExp(r'^[0-9a-f]{40}$').hasMatch(s) ? s.substring(0, 7) : s;
}
