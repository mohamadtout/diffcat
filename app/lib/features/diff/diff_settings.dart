import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';

class DiffSettings {
  const DiffSettings({this.wrap = false, this.fontSize = defaultFontSize});

  static const defaultFontSize = 12.5;
  static const minFontSize = 9.0;
  static const maxFontSize = 22.0;

  final bool wrap;
  final double fontSize;

  DiffSettings copyWith({bool? wrap, double? fontSize}) =>
      DiffSettings(wrap: wrap ?? this.wrap, fontSize: fontSize ?? this.fontSize);
}

final diffSettingsProvider = NotifierProvider<DiffSettingsNotifier, DiffSettings>(DiffSettingsNotifier.new);

class DiffSettingsNotifier extends Notifier<DiffSettings> {
  @override
  DiffSettings build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return DiffSettings(
      wrap: prefs.getBool(StoreKeys.diffWrap) ?? false,
      fontSize: prefs.getDouble(StoreKeys.diffFontSize) ?? DiffSettings.defaultFontSize,
    );
  }

  void toggleWrap() {
    state = state.copyWith(wrap: !state.wrap);
    ref.read(sharedPrefsProvider).setBool(StoreKeys.diffWrap, state.wrap);
  }

  void setFontSize(double size) {
    final clamped = size.clamp(DiffSettings.minFontSize, DiffSettings.maxFontSize);
    if (clamped == state.fontSize) return;
    state = state.copyWith(fontSize: clamped);
    ref.read(sharedPrefsProvider).setDouble(StoreKeys.diffFontSize, clamped);
  }
}
