import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host side of the device tests: saves screenshots taken on the device to
/// `$SCREENSHOT_DIR` (default build/device_screenshots).
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'build/device_screenshots';
    final file = File('$dir/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
