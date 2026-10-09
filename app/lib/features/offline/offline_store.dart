import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../data/github/response_cache.dart';

/// Storage groups inside a saved repo, used for sizes and selective deletes.
abstract final class Groups {
  /// Repo info, branch/tag lists, PR list.
  static const repo = 'repo';
  static const other = 'other';
  static String branch(String name) => 'branch:$name';
  static String files(String branch) => 'files:$branch';
  static String commit(String sha) => 'commit:$sha';
  static String pull(int number) => 'pr:$number';
}

/// Which saved repo, and which part of it, a GitHub request belongs to.
({String repo, String group})? classifyRequest(String path, Map<String, dynamic>? query) {
  final m = RegExp(r'^/repos/([^/]+)/([^/]+)(/.*)?$').firstMatch(path);
  if (m == null) return null;
  final repo = '${m[1]}/${m[2]}';
  final rest = m[3] ?? '';
  RegExpMatch? match(String pattern) => RegExp(pattern).firstMatch(rest);
  final String group;
  if (rest.isEmpty || rest == '/branches' || rest == '/tags' || rest == '/pulls') {
    group = Groups.repo;
  } else if (match(r'^/pulls/(\d+)(/files|/commits)?$') case final p?) {
    group = Groups.pull(int.parse(p[1]!));
  } else if (rest == '/commits' && query?['sha'] != null && query?['path'] == null) {
    group = Groups.branch('${query!['sha']}');
  } else if (match(r'^/commits/([0-9a-fA-F]{7,40})$') case final c?) {
    group = Groups.commit(c[1]!.toLowerCase());
  } else if (match(r'^/git/trees/(.+)$') case final t?) {
    group = Groups.branch(Uri.decodeComponent(t[1]!));
  } else if (rest.startsWith('/contents/') && query?['ref'] != null) {
    group = Groups.files('${query!['ref']}');
  } else {
    group = Groups.other;
  }
  return (repo: repo, group: group);
}

/// What a branch download includes.
class DownloadOptions {
  const DownloadOptions({this.commits = 30, this.pulls = true, this.files = false});

  factory DownloadOptions.fromJson(Map<String, dynamic> j) => DownloadOptions(
    commits: (j['commits'] as int?) ?? 30,
    pulls: (j['pulls'] as bool?) ?? true,
    files: (j['files'] as bool?) ?? false,
  );

  /// How many recent commits get their diffs saved.
  final int commits;

  /// Open pull requests with their diffs and commits.
  final bool pulls;

  /// Every text file at the branch head (one archive download), not just diffs.
  final bool files;

  DownloadOptions copyWith({int? commits, bool? pulls, bool? files}) =>
      DownloadOptions(commits: commits ?? this.commits, pulls: pulls ?? this.pulls, files: files ?? this.files);

  Map<String, dynamic> toJson() => {'commits': commits, 'pulls': pulls, 'files': files};
}

class SavedCommit {
  const SavedCommit(this.sha, this.title);
  factory SavedCommit.fromJson(Map<String, dynamic> j) => SavedCommit(j['sha'] as String, j['title'] as String);
  final String sha;
  final String title;
  Map<String, dynamic> toJson() => {'sha': sha, 'title': title};
}

class SavedBranch {
  SavedBranch({required this.updatedAt, required this.options, required this.commits});

  factory SavedBranch.fromJson(Map<String, dynamic> j) => SavedBranch(
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    options: DownloadOptions.fromJson(j['options'] as Map<String, dynamic>),
    commits: [for (final c in j['commits'] as List<dynamic>) SavedCommit.fromJson(c as Map<String, dynamic>)],
  );

  DateTime updatedAt;
  DownloadOptions options;

  /// The commits this branch's download covered, newest first.
  List<SavedCommit> commits;

  Map<String, dynamic> toJson() => {
    'updatedAt': updatedAt.toIso8601String(),
    'options': options.toJson(),
    'commits': [for (final c in commits) c.toJson()],
  };
}

class SavedEntry {
  const SavedEntry({required this.file, required this.bytes, required this.group});
  factory SavedEntry.fromJson(Map<String, dynamic> j) =>
      SavedEntry(file: j['file'] as String, bytes: j['bytes'] as int, group: j['group'] as String);
  final String file;
  final int bytes;
  final String group;
  Map<String, dynamic> toJson() => {'file': file, 'bytes': bytes, 'group': group};
}

/// Everything saved for one repo.
class SavedRepo {
  SavedRepo(this.fullName, {DateTime? updatedAt, Map<String, SavedBranch>? branches, Map<int, String>? pulls})
    : updatedAt = updatedAt ?? DateTime.now(),
      branches = branches ?? {},
      pulls = pulls ?? {};

  factory SavedRepo.fromJson(Map<String, dynamic> j) =>
      SavedRepo(
          j['repo'] as String,
          updatedAt: DateTime.parse(j['updatedAt'] as String),
          branches: {
            for (final e in (j['branches'] as Map<String, dynamic>).entries)
              e.key: SavedBranch.fromJson(e.value as Map<String, dynamic>),
          },
          pulls: {for (final e in (j['pulls'] as Map<String, dynamic>).entries) int.parse(e.key): e.value as String},
        )
        ..entries.addAll({
          for (final e in (j['entries'] as Map<String, dynamic>).entries)
            e.key: SavedEntry.fromJson(e.value as Map<String, dynamic>),
        });

  final String fullName;
  DateTime updatedAt;
  final Map<String, SavedBranch> branches;

  /// Titles of saved pull requests, by number.
  final Map<int, String> pulls;

  /// Saved responses by request key.
  final Map<String, SavedEntry> entries = {};

  int get bytes => entries.values.fold(0, (s, e) => s + e.bytes);

  int groupBytes(String group) => entries.values.where((e) => e.group == group).fold(0, (s, e) => s + e.bytes);

  bool hasGroup(String group) => entries.values.any((e) => e.group == group);

  /// Size attributable to [branch]: its lists and tree, its files and its
  /// commits' diffs (commits shared with another branch count for both).
  int branchBytes(String branch) {
    final shas = {for (final c in branches[branch]?.commits ?? const <SavedCommit>[]) Groups.commit(c.sha)};
    return entries.values
        .where((e) => e.group == Groups.branch(branch) || e.group == Groups.files(branch) || shas.contains(e.group))
        .fold(0, (s, e) => s + e.bytes);
  }

  Map<String, dynamic> toJson() => {
    'repo': fullName,
    'updatedAt': updatedAt.toIso8601String(),
    'branches': {for (final e in branches.entries) e.key: e.value.toJson()},
    'pulls': {for (final e in pulls.entries) '${e.key}': e.value},
    'entries': {for (final e in entries.entries) e.key: e.value.toJson()},
  };
}

/// Saved responses longer than this are decoded on a background isolate.
const _isolateDecodeChars = 50 * 1024;

Object? _decode(String text) => jsonDecode(text);

/// Offline copies of GitHub responses, one folder per repo:
/// `<root>/<owner>__<name>/index.json` plus one file per response.
///
/// The UI's GitHub client replays from here; downloads record into it.
class OfflineStore extends ChangeNotifier implements ResponseCache {
  OfflineStore._(this.root, this._repos);

  static Future<OfflineStore> open(Directory root) async {
    await root.create(recursive: true);
    final repos = <String, SavedRepo>{};
    await for (final dir in root.list()) {
      if (dir is! Directory) continue;
      final index = File('${dir.path}/index.json');
      if (!await index.exists()) continue;
      try {
        final repo = SavedRepo.fromJson(jsonDecode(await index.readAsString()) as Map<String, dynamic>);
        repos[_id(repo.fullName)] = repo;
      } on Object catch (e) {
        debugPrint('Ignoring unreadable offline index ${index.path}: $e');
      }
    }
    return OfflineStore._(root, repos);
  }

  final Directory root;
  final Map<String, SavedRepo> _repos;
  final _dirty = <String>{};

  static String _id(String fullName) => fullName.toLowerCase();
  Directory _dir(String fullName) => Directory('${root.path}/${_id(fullName).replaceFirst('/', '__')}');

  List<SavedRepo> get repos => _repos.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  SavedRepo? repo(String fullName) => _repos[_id(fullName)];

  int get totalBytes => _repos.values.fold(0, (s, r) => s + r.bytes);

  bool hasCommit(String fullName, String sha) => repo(fullName)?.hasGroup(Groups.commit(sha.toLowerCase())) ?? false;

  static final _repoInKey = RegExp(r'\|/repos/([^/?]+)/([^/?]+)');

  /// Lower-case `owner/name` a request key belongs to, if it's repo-scoped.
  static String? repoOfKey(String key) {
    final m = _repoInKey.firstMatch(key);
    return m == null ? null : _id('${m[1]}/${m[2]}');
  }

  @override
  Future<CachedResponse?> read(String key) async {
    final id = repoOfKey(key);
    final repo = id == null ? null : _repos[id];
    final entry = repo?.entries[key];
    if (repo == null || entry == null) return null;
    try {
      final text = await File('${_dir(repo.fullName).path}/${entry.file}').readAsString();
      // Big saved diffs decode off the UI thread, like Dio does for network responses.
      final j = text.length > _isolateDecodeChars ? await compute(_decode, text) : jsonDecode(text);
      return CachedResponse(data: (j as Map<String, dynamic>)['data'], link: j['link'] as String?);
    } on Object {
      // Missing or corrupt file: forget it and fall back to the network.
      repo.entries.remove(key);
      _dirty.add(_id(repo.fullName));
      return null;
    }
  }

  @override
  Future<void> write(String key, String path, Map<String, dynamic>? query, CachedResponse response) async {
    final owner = classifyRequest(path, query);
    if (owner == null) return;
    final repo = _repos.putIfAbsent(_id(owner.repo), () => SavedRepo(owner.repo));
    final file = '${sha1.convert(utf8.encode(key))}.json';
    final bytes = utf8.encode(jsonEncode({'link': response.link, 'data': response.data}));
    final dir = _dir(repo.fullName);
    await dir.create(recursive: true);
    await File('${dir.path}/$file').writeAsBytes(bytes, flush: false);
    repo.entries[key] = SavedEntry(file: file, bytes: bytes.length, group: owner.group);
    _dirty.add(_id(repo.fullName));
  }

  /// Records what a finished branch download covered.
  void saveBranch(String fullName, String branch, SavedBranch info, {Map<int, String> pulls = const {}}) {
    final repo = _repos.putIfAbsent(_id(fullName), () => SavedRepo(fullName));
    repo.branches[branch] = info;
    repo.pulls.addAll(pulls);
    repo.updatedAt = info.updatedAt;
    _dirty.add(_id(fullName));
  }

  /// Persists index changes and notifies listeners.
  Future<void> flush() async {
    for (final id in _dirty.toList()) {
      final repo = _repos[id];
      if (repo == null) continue;
      final dir = _dir(repo.fullName);
      await dir.create(recursive: true);
      final tmp = File('${dir.path}/index.json.tmp');
      await tmp.writeAsString(jsonEncode(repo.toJson()));
      await tmp.rename('${dir.path}/index.json'); // atomic replace
    }
    _dirty.clear();
    notifyListeners();
  }

  Future<void> deleteRepo(String fullName) async {
    final repo = _repos.remove(_id(fullName));
    _dirty.remove(_id(fullName));
    if (repo != null) {
      final dir = _dir(repo.fullName);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    notifyListeners();
  }

  /// Deletes a branch's lists, tree, files and the diffs of its commits that
  /// no other saved branch covers.
  Future<void> deleteBranch(String fullName, String branch) async {
    final repo = this.repo(fullName);
    if (repo == null) return;
    final own = {for (final c in repo.branches[branch]?.commits ?? const <SavedCommit>[]) c.sha};
    final shared = {
      for (final e in repo.branches.entries)
        if (e.key != branch) ...e.value.commits.map((c) => c.sha),
    };
    final commitGroups = {for (final sha in own.difference(shared)) Groups.commit(sha)};
    repo.branches.remove(branch);
    await _deleteWhere(
      repo,
      (g) => g == Groups.branch(branch) || g == Groups.files(branch) || commitGroups.contains(g),
    );
  }

  Future<void> deleteBranchFiles(String fullName, String branch) async {
    final repo = this.repo(fullName);
    if (repo == null) return;
    repo.branches[branch]?.options = repo.branches[branch]!.options.copyWith(files: false);
    await _deleteWhere(repo, (g) => g == Groups.files(branch));
  }

  Future<void> deleteCommit(String fullName, String sha) async {
    final repo = this.repo(fullName);
    if (repo != null) await _deleteWhere(repo, (g) => g == Groups.commit(sha.toLowerCase()));
  }

  Future<void> deletePull(String fullName, int number) async {
    final repo = this.repo(fullName);
    if (repo == null) return;
    repo.pulls.remove(number);
    await _deleteWhere(repo, (g) => g == Groups.pull(number));
  }

  Future<void> _deleteWhere(SavedRepo repo, bool Function(String group) match) async {
    final dir = _dir(repo.fullName);
    final doomed = repo.entries.entries.where((e) => match(e.value.group)).toList();
    for (final e in doomed) {
      repo.entries.remove(e.key);
      final f = File('${dir.path}/${e.value.file}');
      if (await f.exists()) await f.delete();
    }
    if (repo.branches.isEmpty && repo.entries.values.every((e) => e.group == Groups.repo || e.group == Groups.other)) {
      await deleteRepo(repo.fullName); // nothing meaningful left
      return;
    }
    _dirty.add(_id(repo.fullName));
    await flush();
  }
}

/// Human-readable size: 999 B, 12.3 KB, 4.5 MB.
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var v = bytes / 1000;
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}
