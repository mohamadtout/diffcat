import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'poll_state.dart';

const gitEventsChannelId = 'git_events';
const _channelName = 'Git activity';

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    gitEventsChannelId,
    _channelName,
    channelDescription: 'New commits and pull requests on watched repos',
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(''),
  ),
  iOS: DarwinNotificationDetails(),
);

/// On-device notifications. Works in the app and in the background isolate
/// that runs the poller; tapping one delivers its route to the app.
class LocalNotifications {
  LocalNotifications._(this._plugin);

  /// Inert instance for tests / unsupported platforms.
  LocalNotifications.disabled() : _plugin = null;

  final FlutterLocalNotificationsPlugin? _plugin;
  final _routes = StreamController<String>.broadcast();
  String? _launchRoute;

  bool get enabled => _plugin != null;

  /// Routes from notifications tapped while the app is running.
  Stream<String> get openedRoutes => _routes.stream;

  /// Route of the notification that launched the app (consumed once).
  String? takeLaunchRoute() {
    final r = _launchRoute;
    _launchRoute = null;
    return r;
  }

  static Future<LocalNotifications> init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return LocalNotifications.disabled();
    try {
      final service = LocalNotifications._(FlutterLocalNotificationsPlugin());
      await service._init();
      return service;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      return LocalNotifications.disabled();
    }
  }

  Future<void> _init() async {
    final plugin = _plugin!;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final route = r.payload;
        if (route != null && route.isNotEmpty) _routes.add(route);
      },
    );
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            gitEventsChannelId,
            _channelName,
            description: 'New commits and pull requests on watched repos',
            importance: Importance.high,
          ),
        );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) _launchRoute = launch!.notificationResponse?.payload;
  }

  Future<bool> requestPermission() async {
    final plugin = _plugin;
    if (plugin == null) return false;
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  Future<void> show(GitEvent e) async {
    await _plugin?.show(
      id: e.notificationId,
      title: e.title,
      body: e.body,
      payload: e.route,
      notificationDetails: _details,
    );
  }
}

/// Overridden in main() with the initialised instance.
final localNotificationsProvider = Provider<LocalNotifications>((ref) => LocalNotifications.disabled());
