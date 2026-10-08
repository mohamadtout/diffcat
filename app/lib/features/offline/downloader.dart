import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../data/github/github_api.dart';
import '../../data/github/github_client.dart';
import '../../data/github/models/models.dart';
import '../../data/github/response_cache.dart';
import 'offline_store.dart';

class DownloadProgress {
  const DownloadProgress({required this.phase, this.done = 0, this.total = 0, this.finished = false, this.error});

  final String phase;
  final int done;
  final int total;
  final bool finished;

  /// Set when the download stopped early. What was saved so far is kept.
  final String? error;

  double? get fraction => total == 0 ? null : (done / total).clamp(0, 1);
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Cancelled';
}

/// Saves one branch of a repo for offline reading.
///
/// It requests exactly what the screens request (same [GitHubApi] calls and
/// parameters) through a recording client, so a later read finds each
/// response under the same key. Commit diffs are immutable and skipped when
/// already saved, which makes updates cheap.
class BranchDownloader {
  BranchDownloader({
    required this.store,
    required this.repo,
    required this.branch,
    required this.options,
    required this.onProgress,
    String? token,
    GitHubApi? api,
  }) : api = api ?? GitHubApi(GitHubClient(token: token, cache: store, cacheMode: CacheMode.record));

  final OfflineStore store;
  final GitHubApi api;
  final RepoRef repo;
  final String branch;
  final DownloadOptions options;
  final ValueChanged<DownloadProgress> onProgress;

  /// Same page size as the commit list screen, so pages line up.
  static const pageSize = 30;
  static const _parallel = 4;

  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  String _phase = 'Starting';

  void cancel() => _cancelled = true;

  void _report() => onProgress(DownloadProgress(phase: _phase, done: _done, total: _total));

  Future<T> _step<T>(Future<T> request) async {
    if (_cancelled) throw DownloadCancelled();
    final result = await request;
    _done++;
    _report();
    return result;
  }

  Future<void> run() async {
    final commits = <SavedCommit>[];
    final pulls = <int, String>{};
    var listed = false;
    try {
      _phase = 'Repository';
      _total = 4;
      _report();
      await _step(api.repo(repo));
      await _step(api.branches(repo));
      await _step(api.tags(repo));

      _phase = 'Commit list';
      final pages = (options.commits / pageSize).ceil();
      _total += pages - 1;
      for (var page = 1; page <= pages; page++) {
        final p = await _step(api.commits(repo, ref: branch, page: page, perPage: pageSize));
        commits.addAll(p.items.map((c) => SavedCommit(c.sha, c.title)));
        if (!p.hasNext) break;
      }
      if (commits.length > options.commits) commits.removeRange(options.commits, commits.length);
      listed = true;

      final missing = commits.where((c) => !store.hasCommit(repo.fullName, c.sha)).toList();
      _total += missing.length + 1 + (options.pulls ? 1 : 0) + (options.files ? 1 : 0);
      _phase = 'Diffs';
      for (var i = 0; i < missing.length; i += _parallel) {
        await Future.wait([for (final c in missing.skip(i).take(_parallel)) _step(api.commit(repo, c.sha))]);
      }

      _phase = 'File tree';
      await _step(api.tree(repo, branch));

      if (options.pulls) {
        _phase = 'Pull requests';
        final open = (await _step(api.pulls(repo, state: 'open'))).items;
        _total += open.length * 3;
        for (final p in open) {
          await _step(api.pull(repo, p.number));
          await _step(api.pullFiles(repo, p.number));
          await _step(api.pullCommits(repo, p.number));
          pulls[p.number] = p.title;
        }
      }

      if (options.files) {
        _phase = 'Files';
        _report();
        final archive = await _step(api.tarball(repo, branch));
        final files = await compute(extractTextFiles, archive);
        for (final f in files.entries) {
          if (_cancelled) throw DownloadCancelled();
          final path = GitHubApi.contentsPath(repo, f.key);
          final query = {'ref': branch};
          await store.write(
            GitHubClient.cacheKey(path, query: query, accept: GitHubClient.rawAccept),
            path,
            query,
            CachedResponse(data: f.value),
          );
        }
      }
      onProgress(DownloadProgress(phase: 'Done', done: _total, total: _total, finished: true));
    } on Object catch (e) {
      onProgress(DownloadProgress(phase: _phase, done: _done, total: _total, finished: true, error: e.toString()));
      rethrow;
    } finally {
      if (listed) {
        store.saveBranch(
          repo.fullName,
          branch,
          SavedBranch(updatedAt: DateTime.now(), options: options, commits: commits),
          pulls: pulls,
        );
      }
      await store.flush();
    }
  }
}

/// Text files of a GitHub tarball by repo path. Binary files (containing NUL)
/// and files over [maxBytes] are skipped, as the file viewer can't show them.
Map<String, String> extractTextFiles(List<int> tarGz, {int maxBytes = 1000000}) {
  final archive = TarDecoder().decodeBytes(const GZipDecoder().decodeBytes(tarGz));
  final out = <String, String>{};
  for (final f in archive.files) {
    if (!f.isFile) continue;
    // Entries are `<owner>-<repo>-<sha>/<path>`.
    final slash = f.name.indexOf('/');
    if (slash < 0 || slash == f.name.length - 1) continue;
    final bytes = f.content;
    if (bytes.length > maxBytes || bytes.contains(0)) continue;
    out[f.name.substring(slash + 1)] = utf8.decode(bytes, allowMalformed: true);
  }
  return out;
}
