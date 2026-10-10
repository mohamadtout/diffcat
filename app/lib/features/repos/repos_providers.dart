import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../notifications/watch_controller.dart';
import 'repo_library.dart';

/// Your repositories, most recently pushed first (up to 1,000). Only the
/// kinds chosen under Settings → Repository list are requested; unchanged
/// pages answer 304 and cost no rate limit.
final myReposProvider = FutureProvider<List<GhRepo>>((ref) async {
  final api = ref.watch(githubApiProvider);
  final affiliation = ref.watch(repoLibraryProvider.select((l) => l.sources.affiliation));
  if (affiliation.isEmpty) return const [];
  final out = <GhRepo>[];
  for (var page = 1; page <= 10; page++) {
    final p = await api.myRepos(page: page, affiliation: affiliation);
    out.addAll(p.items);
    if (!p.hasNext) break;
  }
  return out;
});

final pinnedReposProvider = NotifierProvider<PinnedRepos, List<String>>(PinnedRepos.new);

class PinnedRepos extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(sharedPrefsProvider).getStringList(StoreKeys.pinnedRepos) ?? const [];

  bool isPinned(String fullName) => state.any((e) => e.toLowerCase() == fullName.toLowerCase());

  Future<void> toggle(String fullName) =>
      isPinned(fullName) ? removeAll({fullName.toLowerCase()}) : setPinned([fullName], pinned: true);

  Future<void> setPinned(Iterable<String> repos, {required bool pinned}) async {
    if (!pinned) return removeAll(repos.map((r) => r.toLowerCase()).toSet());
    await _save([...state, ...repos.where((r) => !isPinned(r))]);
  }

  /// Unpins several repos (lower-case `owner/name`).
  Future<void> removeAll(Set<String> keys) async {
    if (state.any((e) => keys.contains(e.toLowerCase()))) {
      await _save(state.where((e) => !keys.contains(e.toLowerCase())).toList());
    }
  }

  /// Puts back an earlier list (Undo).
  Future<void> restore(List<String> list) => _save(list);

  Future<void> _save(List<String> list) async {
    state = list;
    await ref.read(sharedPrefsProvider).setStringList(StoreKeys.pinnedRepos, list);
  }
}

/// Repos opened recently, newest first. The signed-out home screen lists them.
final recentReposProvider = NotifierProvider<RecentRepos, List<String>>(RecentRepos.new);

class RecentRepos extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(sharedPrefsProvider).getStringList(StoreKeys.recentRepos) ?? const [];

  Future<void> add(RepoRef repo) => _save(pushRecent(state, repo.fullName));

  Future<void> remove(String fullName) => _save(state.where((e) => e != fullName).toList());

  Future<void> _save(List<String> list) async {
    state = list;
    await ref.read(sharedPrefsProvider).setStringList(StoreKeys.recentRepos, list);
  }
}

/// Moves [fullName] to the front (case-insensitively unique), keeping [max].
List<String> pushRecent(List<String> list, String fullName, {int max = 20}) =>
    [fullName, ...list.where((e) => e.toLowerCase() != fullName.toLowerCase())].take(max).toList();

/// Your repos followed by downloaded repos that aren't among them.
List<GhRepo> mergeRepos(List<GhRepo> mine, List<GhRepo> saved) {
  final names = {for (final r in mine) r.fullName.toLowerCase()};
  return [...mine, ...saved.where((r) => !names.contains(r.fullName.toLowerCase()))];
}

/// How the user organized the repo list (folders, archive, hidden, sources).
final repoLibraryProvider = NotifierProvider<RepoLibraryNotifier, RepoLibrary>(RepoLibraryNotifier.new);

class RepoLibraryNotifier extends Notifier<RepoLibrary> {
  @override
  RepoLibrary build() => RepoLibrary.parse(ref.watch(sharedPrefsProvider).getString(StoreKeys.repoLibrary));

  /// Replaces the whole library (also how Undo restores the previous one).
  void set(RepoLibrary library) {
    state = library;
    ref.read(sharedPrefsProvider).setString(StoreKeys.repoLibrary, jsonEncode(library.toJson()));
  }

  void update(RepoLibrary Function(RepoLibrary l) change) => set(change(state));

  /// A new folder, last in the list. Returns its id.
  String createFolder(String name, Color color) {
    final id = 'f${DateTime.now().microsecondsSinceEpoch}';
    update((l) => l.withFolder(RepoFolder(id: id, name: name, color: color)));
    return id;
  }

  /// Hides [repos]: they also stop being watched and pinned, since hidden
  /// repos never show or notify.
  Future<void> hide(Iterable<String> repos) async {
    final list = repos.toList();
    update((l) => l.setHidden(list, hide: true));
    await _forget(list.map(RepoLibrary.key).toSet());
  }

  /// Hides every repo of [login] (a user or organization), as [hide] does.
  Future<void> hideOwner(String login) async {
    update((l) => l.setOwnerHidden(login, hide: true));
    final prefix = '${RepoLibrary.key(login)}/';
    final watched = ref.read(watchedReposProvider).where((r) => r.startsWith(prefix));
    final pinned = ref.read(pinnedReposProvider).where((r) => RepoLibrary.key(r).startsWith(prefix));
    await _forget({...watched, ...pinned.map(RepoLibrary.key)});
  }

  Future<void> _forget(Set<String> keys) async {
    await ref.read(watchedReposProvider.notifier).unwatchAll(keys);
    await ref.read(pinnedReposProvider.notifier).removeAll(keys);
  }
}
