import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/diff/diff_colors.dart';
import 'features/notifications/local_notifications.dart';
import 'features/notifications/watch_controller.dart';
import 'features/settings/settings_screen.dart';

class GitReviewerApp extends ConsumerStatefulWidget {
  const GitReviewerApp({super.key});

  @override
  ConsumerState<GitReviewerApp> createState() => _GitReviewerAppState();
}

class _GitReviewerAppState extends ConsumerState<GitReviewerApp> {
  StreamSubscription<String>? _notificationTaps;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Notification tapped while the app is running → open its target.
    _notificationTaps = ref
        .read(localNotificationsProvider)
        .openedRoutes
        .listen((route) => ref.read(routerProvider).go(route));
    // Opening the app is a free chance to check (and the only one on iOS for now),
    // and while it's open the inbox is checked about every minute.
    _lifecycle = AppLifecycleListener(onResume: _foreground, onHide: _background);
    WidgetsBinding.instance.addPostFrameCallback((_) => _foreground());
  }

  void _foreground() {
    final polls = ref.read(pollControllerProvider.notifier)..setForeground(true);
    polls.checkIfStale();
  }

  void _background() => ref.read(pollControllerProvider.notifier).setForeground(false);

  @override
  void dispose() {
    _notificationTaps?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(diffColorsProvider);
    return MaterialApp.router(
      title: 'Diffcat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(diff: colors.lightColors),
      darkTheme: AppTheme.dark(diff: colors.darkColors),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
