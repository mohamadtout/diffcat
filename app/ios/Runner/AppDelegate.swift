import Flutter
import UIKit
import workmanager_apple

/// Must match `_taskName` in lib/features/notifications/background.dart and
/// BGTaskSchedulerPermittedIdentifiers in Info.plist.
private let backgroundPollTask = "git-reviewer-poll"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background checks run in a headless engine that needs the plugins too
    // (secure storage, prefs, notifications).
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // BGTaskScheduler handlers must be registered before launch finishes.
    // iOS decides when the refresh runs; ask for no sooner than 15 minutes.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: backgroundPollTask, earliestBeginInSeconds: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerLaunchHandlers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
