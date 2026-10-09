import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Marks [dir] as excluded from iCloud backups (iOS; Android excludes all app
/// data in the manifest). Failures are logged, never thrown: the folder still
/// works, it's just backed up.
Future<void> excludeFromBackup(Directory dir) async {
  if (kIsWeb || !Platform.isIOS) return;
  try {
    await const MethodChannel('diffcat/backup').invokeMethod<bool>('exclude', dir.path);
  } on Object catch (e) {
    debugPrint('Could not exclude ${dir.path} from backup: $e');
  }
}
