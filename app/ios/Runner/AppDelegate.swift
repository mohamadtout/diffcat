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
    // Keeps offline copies (possibly private code) out of iCloud backups.
    // Called from lib/core/storage/backup_exclusion.dart.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DiffcatBackup") else { return }
    let channel = FlutterMethodChannel(name: "diffcat/backup", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "exclude", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
