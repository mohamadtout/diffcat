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

/// The requests that make one pull request readable offline: what its screen
/// loads (details, files diff, commits) plus its reviews and line comments.
List<Future<Object?> Function()> pullRequestCalls(GitHubApi api, RepoRef repo, int number) => [
  () => api.pull(repo, number),
  () => api.pullFiles(repo, number),
  () => api.pullCommits(repo, number),
  () => api.reviews(repo, number),
  () => api.reviewComments(repo, number),
];

/// Saves one pull request, open or closed, on its own (its screen's download
/// button), plus the repo's details so the repo opens offline.
class PullDownloader {
  PullDownloader({
    required this.store,
    required this.repo,
    required this.number,
    required this.onProgress,
    String? token,
    GitHubApi? api,
  }) : api = api ?? GitHubApi(GitHubClient(token: token, cache: store, cacheMode: CacheMode.record));

  final OfflineStore store;
  final GitHubApi api;
  final RepoRef repo;
  final int number;
  final ValueChanged<DownloadProgress> onProgress;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  Future<void> run() async {
    final calls = [() => api.repo(repo), ...pullRequestCalls(api, repo, number)];
    var done = 0;
    try {
      String? title;
      for (final call in calls) {
        if (_cancelled) throw DownloadCancelled();
        onProgress(DownloadProgress(phase: 'Pull request #$number', done: done, total: calls.length));
        final result = await call();
        if (result is GhPull) title = result.title;
        done++;
      }
      store.savePull(repo.fullName, number, title ?? '#$number');
      onProgress(DownloadProgress(phase: 'Done', done: done, total: calls.length, finished: true));
    } on Object catch (e) {
      onProgress(
        DownloadProgress(phase: 'Pull request #$number', done: done, total: calls.length, finished: true, error: '$e'),
      );
      rethrow;
    } finally {
      await store.flush();
    }
  }
}

/// [CommitRange.since] didn't find its commit.
class SinceCommitNotFound implements Exception {
  SinceCommitNotFound(this.sha, this.branch, this.searched);
  final String sha;
  final String branch;
  final int searched;

  @override
  String toString() =>
      'Commit ${shortSha(sha)} isn\'t in the ${searched == 1 ? 'only commit' : 'last $searched commits'} of $branch';
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

  /// How far back [CommitRange.since] looks for its commit (100 pages).
  static const maxSinceCommits = 3000;
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
      await _listCommits(commits);
      listed = true;

      final missing = commits.where((c) => !store.hasCommit(repo.fullName, c.sha)).toList();
      final lists = switch (options.pulls) {
        PullScope.none => <String>[],
        PullScope.open => ['open'],
        PullScope.openAndClosed => ['open', 'closed', 'all'],
      };
      _total += missing.length + 1 + lists.length + (options.files ? 1 : 0);
      _phase = 'Diffs';
      for (var i = 0; i < missing.length; i += _parallel) {
        await Future.wait([for (final c in missing.skip(i).take(_parallel)) _step(api.commit(repo, c.sha))]);
      }

      _phase = 'File tree';
      await _step(api.tree(repo, branch));

      if (lists.isNotEmpty) {
        _phase = 'Pull requests';
        // Each filter's list as the PR tab shows it; the PRs themselves once.
        final wanted = <int, GhPull>{};
        for (final state in lists) {
          for (final p in (await _step(api.pulls(repo, state: state))).items) {
            if (state != 'all') wanted[p.number] = p;
          }
        }
        _total += wanted.length * 5;
        for (final p in wanted.values) {
          for (final call in pullRequestCalls(api, repo, p.number)) {
            await _step(call());
          }
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

extension on BranchDownloader {
  /// Pages through [branch]'s history into [out], as far as the options ask.
  Future<void> _listCommits(List<SavedCommit> out) async {
    final since = options.since?.trim().toLowerCase() ?? '';
    final maxPages = switch (options.range) {
      CommitRange.recent => (options.commits.clamp(1, DownloadOptions.maxCommits) / BranchDownloader.pageSize).ceil(),
      CommitRange.since => BranchDownloader.maxSinceCommits ~/ BranchDownloader.pageSize,
      CommitRange.all => 1 << 30,
    };
    for (var page = 1; page <= maxPages; page++) {
      if (page > 1) _total++;
      final p = await _step(api.commits(repo, ref: branch, page: page, perPage: BranchDownloader.pageSize));
      out.addAll(p.items.map((c) => SavedCommit(c.sha, c.title)));
      if (options.range == CommitRange.since) {
        final found = out.indexWhere((c) => c.sha.toLowerCase().startsWith(since));
        if (since.isNotEmpty && found >= 0) {
          out.removeRange(found + 1, out.length);
          return;
        }
      }
      if (!p.hasNext) break;
    }
    if (options.range == CommitRange.since) throw SinceCommitNotFound(since, branch, out.length);
    if (options.range == CommitRange.recent && out.length > options.commits) {
      out.removeRange(options.commits, out.length);
    }
  }
}

/// Size of the text files an "All files" download would keep.
class FilesEstimate {
  const FilesEstimate({required this.files, required this.bytes, required this.truncated});
  final int files;
  final int bytes;

  /// GitHub cut the tree short (huge repo), so it's a lower bound.
  final bool truncated;
}

/// Extensions that are almost always binary, which [extractTextFiles] drops.
const _binaryExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'ico',
  'icns',
  'bmp',
  'tiff',
  'psd',
  'pdf',
  'zip',
  'gz',
  'tgz',
  'bz2',
  'xz',
  '7z',
  'rar',
  'jar',
  'aar',
  'apk',
  'ipa',
  'so',
  'dylib',
  'dll',
  'exe',
  'bin',
  'o',
  'a',
  'class',
  'woff',
  'woff2',
  'ttf',
  'otf',
  'eot',
  'mp3',
  'mp4',
  'mov',
  'wav',
  'ogg',
  'webm',
  'avi',
  'sqlite',
  'db',
  'keystore',
  'jks',
};

/// Estimates [extractTextFiles]' result from a tree: files up to [maxBytes]
/// that don't look binary by extension. Saved as JSON, so a little bigger.
FilesEstimate estimateTextFiles(GhTree tree, {int maxBytes = 1000000}) {
  var files = 0;
  var bytes = 0;
  for (final e in tree.entries) {
    final size = e.size;
    if (e.type != TreeEntryType.blob || size == null || size > maxBytes) continue;
    final name = e.path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0 && _binaryExtensions.contains(name.substring(dot + 1).toLowerCase())) continue;
    files++;
    bytes += size;
  }
  return FilesEstimate(files: files, bytes: (bytes * 1.05).round(), truncated: tree.truncated);
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
