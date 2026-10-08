import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/storage/storage.dart';
import '../../data/github/github_api.dart';
import '../../data/github/github_client.dart';
import 'local_notifications.dart';
import 'poller.dart';

const _taskName = 'git-reviewer-poll';

/// Android's minimum for periodic background work. The OS may stretch it
/// (Doze, battery saver), which is why notifications can be late.
const pollInterval = Duration(minutes: 15);

/// Runs the poller and posts a notification per event. Shared by the
/// background task and the in-app "Check now".
Future<PollResult> pollAndNotify({
  required GitHubApi api,
  required SharedPreferences prefs,
  required LocalNotifications notifications,
}) async {
  final result = await Poller(api: api, prefs: prefs).run();
  for (final e in result.events) {
    await notifications.show(e);
  }
  return result;
}

/// Entry point of the background isolate WorkManager starts.
@pragma('vm:entry-point')
void backgroundPollDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await const FlutterSecureStorage().read(key: StoreKeys.githubToken);
      // Signed out still works for public repos, at GitHub's lower rate limit.
      await pollAndNotify(
        api: GitHubApi(GitHubClient(token: token)),
        prefs: prefs,
        notifications: await LocalNotifications.init(),
      );
    } catch (e, s) {
      debugPrint('Background poll failed: $e\n$s');
    }
    // Always report success: a failed check is simply retried next period,
    // and "failure" would make WorkManager back off exponentially.
    return true;
  });
}

/// Schedules (or cancels) the periodic background check.
///
/// Android: WorkManager, every [pollInterval] or later. iOS: a BGAppRefreshTask
/// registered in AppDelegate.swift; iOS picks the time (a few times a day).
abstract final class BackgroundPolling {
  static bool _initialized = false;

  static Future<void> sync({required bool enabled}) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      if (!_initialized) {
        await Workmanager().initialize(backgroundPollDispatcher);
        _initialized = true;
      }
      if (enabled) {
        await Workmanager().registerPeriodicTask(
          _taskName,
          _taskName,
          frequency: pollInterval,
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        );
      } else {
        await Workmanager().cancelByUniqueName(_taskName);
      }
    } catch (e) {
      debugPrint('Could not schedule background checks: $e');
    }
  }
}
