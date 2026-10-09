import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/storage.dart';
import 'core/theme/code_fonts.dart';
import 'data/github/github_exception.dart';
import 'features/notifications/background.dart';
import 'features/notifications/local_notifications.dart';
import 'features/offline/offline_providers.dart';
import 'features/offline/offline_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorSafetyNet();
  CodeFont.registerLicenses();
  final prefs = await SharedPreferences.getInstance();
  final notifications = await LocalNotifications.init();
  final offline = await _openOfflineStore();
  // Keep the periodic background check registered while anything is watched.
  await BackgroundPolling.sync(enabled: (prefs.getStringList(StoreKeys.watchedRepos) ?? const []).isNotEmpty);

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        localNotificationsProvider.overrideWithValue(notifications),
        offlineStoreProvider.overrideWithValue(offline),
      ],
      // Only retry transient failures; 401/404/rate-limit won't fix themselves.
      retry: (count, error) => count < 3 && (error is! GitHubException || error.isRetryable)
          ? Duration(milliseconds: 400 * (1 << count))
          : null,
      child: const GitReviewerApp(),
    ),
  );
}

/// Offline copies live in app support storage. Without it the app still works,
/// just without downloads.
Future<OfflineStore?> _openOfflineStore() async {
  try {
    return await OfflineStore.open(Directory('${(await getApplicationSupportDirectory()).path}/offline'));
  } on Object catch (e) {
    debugPrint('Offline storage unavailable: $e');
    return null;
  }
}

/// Keeps a single failure from taking the app down.
///
/// - Async errors nobody awaited are logged instead of crashing the isolate.
/// - A widget that throws while building renders a small inline error card in
///   its place (the rest of the screen keeps working) instead of the full red
///   screen. Details still go to the debug console via FlutterError.
void _installErrorSafetyNet() {
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    return true;
  };
  ErrorWidget.builder = (details) => Material(
    color: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              kDebugMode ? 'Render error: ${details.exceptionAsString()}' : 'Something went wrong showing this.',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
