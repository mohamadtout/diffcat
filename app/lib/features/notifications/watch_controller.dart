import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';
import '../../data/github/models/repo.dart';
import '../auth/auth_controller.dart';
import 'background.dart';
import 'local_notifications.dart';

/// Repos (`owner/name`, lowercase) this device checks for new commits & PRs.
final watchedReposProvider = NotifierProvider<WatchedRepos, Set<String>>(WatchedRepos.new);

class WatchedRepos extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.watch(sharedPrefsProvider).getStringList(StoreKeys.watchedRepos) ?? const []).toSet();

  bool isWatched(RepoRef r) => state.contains(r.fullName.toLowerCase());

  /// Starts watching: asks for notification permission, schedules background
  /// checks and records a baseline right away (the first check of a repo is
  /// silent, so only activity after this moment notifies).
  Future<String> watch(RepoRef r) async {
    final granted = await ref.read(localNotificationsProvider).requestPermission();
    await _save({...state, r.fullName.toLowerCase()});
    await ref.read(pollControllerProvider.notifier).checkNow();
    return granted
        ? 'Watching. Checks run about every ${pollInterval.inMinutes} min.'
        : 'Watching, but notifications are blocked — allow them in system settings.';
  }

  Future<void> unwatch(RepoRef r) => _save({...state}..remove(r.fullName.toLowerCase()));

  Future<void> _save(Set<String> s) async {
    state = s;
    await ref.read(sharedPrefsProvider).setStringList(StoreKeys.watchedRepos, s.toList()..sort());
    await BackgroundPolling.sync(enabled: s.isNotEmpty);
  }
}

/// Whether your own commits/PRs notify too (default: no).
final notifyIncludeOwnProvider = NotifierProvider<NotifyIncludeOwn, bool>(NotifyIncludeOwn.new);

class NotifyIncludeOwn extends Notifier<bool> {
  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(StoreKeys.notifyIncludeOwn) ?? false;

  Future<void> set(bool v) async {
    state = v;
    await ref.read(sharedPrefsProvider).setBool(StoreKeys.notifyIncludeOwn, v);
  }
}

/// Summary of the most recent check (from either isolate).
class LastPoll {
  const LastPoll({required this.at, required this.events, required this.errors});

  final DateTime at;
  final int events;
  final Map<String, String> errors;
}

class PollStatus {
  const PollStatus({this.last, this.running = false});
  final LastPoll? last;
  final bool running;
}

final pollControllerProvider = NotifierProvider<PollController, PollStatus>(PollController.new);

class PollController extends Notifier<PollStatus> {
  @override
  PollStatus build() => PollStatus(last: _readLast());

  LastPoll? _readLast() {
    final raw = ref.read(sharedPrefsProvider).getString(StoreKeys.lastPoll);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return LastPoll(
        at: DateTime.parse(j['at'] as String),
        events: j['n'] as int? ?? 0,
        errors: (j['e'] as Map<String, dynamic>? ?? const {}).cast<String, String>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Runs a check now. Never throws; failures land in the result's errors.
  Future<void> checkNow() async {
    if (state.running) return;
    state = PollStatus(last: state.last, running: true);
    LastPoll last;
    try {
      final r = await pollAndNotify(
        api: ref.read(liveGithubApiProvider),
        prefs: ref.read(sharedPrefsProvider),
        notifications: ref.read(localNotificationsProvider),
      );
      last = LastPoll(at: r.at, events: r.events.length, errors: r.errors);
    } catch (e) {
      last = LastPoll(at: DateTime.now(), events: 0, errors: {'all': e.toString()});
    }
    if (ref.mounted) state = PollStatus(last: last);
  }

  /// Called when the app returns to the foreground.
  Future<void> checkIfStale({Duration maxAge = const Duration(minutes: 10)}) async {
    if (ref.read(watchedReposProvider).isEmpty || !ref.read(authTokenProvider).hasValue) return;
    await ref.read(sharedPrefsProvider).reload();
    final last = _readLast();
    state = PollStatus(last: last, running: state.running);
    if (last == null || DateTime.now().difference(last.at) > maxAge) await checkNow();
  }
}
