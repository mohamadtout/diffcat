import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/storage.dart';
import '../../data/github/github_api.dart';
import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../repos/repo_library.dart';
import 'poll_state.dart';

/// Max notifications per repo per check, so a big batch of branch updates
/// after a long offline period doesn't flood the shade.
const _maxEventsPerRepo = 5;

/// Repos checked at the same time.
const _parallelRepos = 4;

/// How many PR snapshots to remember per repo.
const _maxPullSnapshots = 200;

class PollResult {
  const PollResult({required this.events, required this.errors, required this.checked, required this.at});

  final List<GitEvent> events;

  /// `owner/name` → error message for repos that couldn't be checked.
  final Map<String, String> errors;
  final int checked;
  final DateTime at;

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'n': events.length, 'c': checked, 'e': errors};
}

/// Checks every watched repo against GitHub and returns what's new since the
/// last check. Runs in the app (Check now / on resume) and in the background
/// isolate (WorkManager). See docs/notifications.md.
///
/// Cost per repo per check: 2 requests (branches + PRs) plus 1 per branch
/// that moved.
class Poller {
  Poller({required this.api, required this.prefs, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final GitHubApi api;
  final SharedPreferences prefs;
  final DateTime Function() _now;

  Future<PollResult> run() async {
    await prefs.reload(); // the other isolate may have written since we started
    final watched = prefs.getStringList(StoreKeys.watchedRepos) ?? const [];
    final states = _loadStates();
    final includeOwn = prefs.getBool(StoreKeys.notifyIncludeOwn) ?? false;
    final self = includeOwn ? null : await _selfLogin();

    // A few repos at a time: iOS gives a background refresh about 30 seconds.
    final perRepo = <String, List<GitEvent>>{};
    final errors = <String, String>{};
    final queue = [...watched];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final fullName = queue.removeAt(0);
        final parts = fullName.split('/');
        if (parts.length != 2) continue;
        final repo = (owner: parts[0], name: parts[1]);
        final state = states[fullName] ?? RepoPollState();
        try {
          perRepo[fullName] = (await checkRepo(repo, state, selfLogin: self)).take(_maxEventsPerRepo).toList();
          states[fullName] = state;
        } catch (e) {
          errors[fullName] = e.toString();
        }
      }
    }

    await Future.wait([for (var i = 0; i < _parallelRepos; i++) worker()]);
    // In watched order, whatever order the checks finished in.
    final events = [for (final r in watched) ...?perRepo[r]];
    if (inboxWanted) {
      try {
        events.addAll((await inbox()).take(_maxEventsPerRepo));
      } catch (e) {
        errors['Review requests'] = e.toString();
      }
    }
    // Forget repos that are no longer watched.
    states.removeWhere((k, _) => !watched.contains(k));
    await _saveStates(states);

    final result = PollResult(events: events, errors: errors, checked: watched.length, at: _now());
    await prefs.setString(StoreKeys.lastPoll, jsonEncode(result.toJson()));
    return result;
  }

  /// Updates [state] in place. The first check of a repo only records a
  /// baseline (no notifications for history that predates watching).
  Future<List<GitEvent>> checkRepo(RepoRef repo, RepoPollState state, {String? selfLogin}) async {
    final checkedAt = _now();
    final branches = await api.branches(repo);
    final pulls = (await api.pulls(repo, state: 'all')).items;

    final events = <GitEvent>[];
    if (state.isSeeded) {
      for (final move in diffBranches(state.branches, branches)) {
        final e = await _branchEvent(repo, move, selfLogin);
        if (e != null) events.add(e);
      }
      events.addAll(pullEvents(repo, state.pulls, pulls, since: state.checkedAt!, selfLogin: selfLogin));
    }

    state.branches
      ..clear()
      ..addAll({for (final b in branches) b.name: b.sha});
    for (final p in pulls) {
      state.pulls[p.number] = PullSnapshot.of(p);
    }
    if (state.pulls.length > _maxPullSnapshots) {
      final keep = (state.pulls.keys.toList()..sort()).reversed.take(_maxPullSnapshots).toSet();
      state.pulls.removeWhere((n, _) => !keep.contains(n));
    }
    state.checkedAt = checkedAt;
    return events;
  }

  Future<GitEvent?> _branchEvent(RepoRef repo, BranchMove move, String? self) async {
    bool keep(GhCommit c) =>
        !isBotLogin(c.authorLogin) && (self == null || c.authorLogin?.toLowerCase() != self.toLowerCase());

    if (move.from == null) {
      // New branch: report its head commit.
      final head = (await api.commits(repo, ref: move.to, perPage: 1)).items.firstOrNull;
      if (head == null || !keep(head)) return null;
      return pushEvent(repo, branch: move.branch, from: null, to: move.to, commits: [head]);
    }
    final cmp = await api.compare(repo, move.from!, move.to);
    if (cmp.status == 'behind' || cmp.status == 'identical') return null; // reset backwards
    return pushEvent(
      repo,
      branch: move.branch,
      from: move.from,
      to: move.to,
      commits: cmp.commits.where(keep).toList(),
      forced: cmp.status == 'diverged',
    );
  }

  /// Whether pull request notifications from the user's inbox are on (Settings
  /// → Notifications; needs a token).
  bool get inboxWanted => (prefs.getBool(StoreKeys.notifyReviewRequests) ?? false) && !api.client.isAnonymous;

  /// New activity on pull requests the user takes part in, on any repo: review
  /// requests, mentions, replies. One conditional request to the notifications
  /// inbox (free when nothing changed). Fine-grained tokens can't read the
  /// inbox, so for them it falls back to searching for review requests.
  Future<List<GitEvent>> inbox() async {
    await prefs.reload();
    final List<GhNotification> threads;
    try {
      threads = await api.notifications();
    } on GitHubException catch (e) {
      if (e.statusCode == 403 || e.statusCode == 404) return _reviewRequests();
      rethrow;
    }
    final raw = prefs.getString(StoreKeys.inboxSeen);
    final seen = raw == null ? null : (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
    final library = RepoLibrary.parse(prefs.getString(StoreKeys.repoLibrary));
    final r = inboxEvents(seen, [
      for (final t in threads)
        if (!library.isHidden(t.repo.fullName)) t,
    ]);
    await prefs.setString(StoreKeys.inboxSeen, jsonEncode(r.seen));
    return r.events;
  }

  /// New requests for the user's review, on any repo (one search request).
  Future<List<GitEvent>> _reviewRequests() async {
    final library = RepoLibrary.parse(prefs.getString(StoreKeys.repoLibrary));
    final now = [
      for (final p in (await api.searchPulls('review-requested:@me')).items)
        if (!library.isHidden(p.repo.fullName)) p,
    ];
    final seen = prefs.getStringList(StoreKeys.reviewRequestsSeen)?.toSet();
    await prefs.setStringList(StoreKeys.reviewRequestsSeen, [for (final p in now) p.key]);
    return reviewRequestEvents(seen, now);
  }

  Future<String?> _selfLogin() async {
    final cached = prefs.getString(StoreKeys.viewerLogin);
    if (cached != null) return cached;
    try {
      final login = (await api.viewer()).login;
      await prefs.setString(StoreKeys.viewerLogin, login);
      return login;
    } catch (_) {
      return null;
    }
  }

  Map<String, RepoPollState> _loadStates() {
    final raw = prefs.getString(StoreKeys.pollState);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: RepoPollState.fromJson(e.value as Map<String, dynamic>),
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _saveStates(Map<String, RepoPollState> states) =>
      prefs.setString(StoreKeys.pollState, jsonEncode({for (final e in states.entries) e.key: e.value.toJson()}));
}
