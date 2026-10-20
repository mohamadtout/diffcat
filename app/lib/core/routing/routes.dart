import '../../data/github/models/repo.dart';

/// Route path builders. Every screen is reachable by URL so that
/// notifications (and future deep links / iPad multi-window) can open it.
///
/// See docs/architecture.md#routing for the full table.
abstract final class Routes {
  static const splash = '/';
  static const setup = '/setup';
  static const repos = '/repos';
  static const inbox = '/inbox';
  static const terminal = '/terminal';
  static const settings = '/settings';
  static const commands = '/settings/commands';
  static const downloads = '/settings/downloads';
  static const terminalAppearance = '/settings/terminal';
  static const codeView = '/settings/code';
  static const repoList = '/settings/repos';
  static const repoFolders = '/settings/repos/folders';

  /// Storage of one downloaded repo.
  static String savedRepo(RepoRef r) => '$downloads/${r.owner}/${r.name}';

  static String _base(RepoRef r) => '/repos/${r.owner}/${r.name}';

  static String _q(Map<String, String?> q) {
    final entries = q.entries.where((e) => e.value != null && e.value!.isNotEmpty);
    if (entries.isEmpty) return '';
    return '?${Uri(queryParameters: {for (final e in entries) e.key: e.value}).query}';
  }

  /// Repo home. [tab] is one of `commits`, `files`, `pulls`, `actions`, `console`.
  static String repo(RepoRef r, {String? tab, String? ref}) => '${_base(r)}${_q({'tab': tab, 'ref': ref})}';

  static String commit(RepoRef r, String sha, {String? file}) => '${_base(r)}/commit/$sha${_q({'file': file})}';

  static String compare(RepoRef r, String base, String head, {String? file}) =>
      '${_base(r)}/compare${_q({'base': base, 'head': head, 'file': file})}';

  static String pull(RepoRef r, int number) => '${_base(r)}/pull/$number';

  /// A workflow run (GitHub Actions): its jobs and steps.
  static String run(RepoRef r, int id) => '${_base(r)}/actions/runs/$id';

  /// One job's log.
  static String jobLog(RepoRef r, int id) => '${_base(r)}/actions/jobs/$id';

  /// [blame] opens with the blame gutter on.
  static String file(RepoRef r, String path, String ref, {bool blame = false}) =>
      '${_base(r)}/file${_q({'path': path, 'ref': ref, 'blame': blame ? '1' : null})}';

  static String history(RepoRef r, String path, String ref) => '${_base(r)}/history${_q({'path': path, 'ref': ref})}';

  static String changedSince(RepoRef r, {String? ref, String? base}) =>
      '${_base(r)}/since${_q({'ref': ref, 'base': base})}';

  /// The in-app screen for a github.com link to a repo, pull request or
  /// commit, or null when the app has no screen for it (issues, wikis…).
  static String? fromGitHubUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.host == 'github.com' || uri.host == 'www.github.com')) return null;
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (s.length < 2) return null;
    final r = (owner: s[0], name: s[1]);
    if (s.length == 2) return repo(r);
    if (s.length >= 4 && s[2] == 'pull' && int.tryParse(s[3]) != null) return pull(r, int.parse(s[3]));
    if (s.length >= 4 && s[2] == 'commit' && RegExp(r'^[0-9a-f]{7,40}$').hasMatch(s[3])) return commit(r, s[3]);
    return null;
  }

  static String terminalSession(String hostId) => '$terminal/$hostId';
  static String hostEdit(String? hostId) => '$terminal/edit${_q({'id': hostId})}';
}
