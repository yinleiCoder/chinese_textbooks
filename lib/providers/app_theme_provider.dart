import 'package:flutter/material.dart';

import '../services/logger/app_logger.dart';
import '../services/storage/key_value_store.dart';
import '../values/values.dart';

/// 主题状态。
///
/// 用 [ChangeNotifier] 而不是更复杂的方案，是因为这里只有一个字段：
/// 引入额外的抽象层只会增加阅读成本，收益为零。
///
/// 持久化策略：**先通知 UI，再落盘**。用户点下"深色"应当立刻看到变化，
/// 存储写入是附带动作；即使写失败，本次会话的体验也不受影响。
final class AppThemeProvider extends ChangeNotifier {
  AppThemeProvider({
    required this._store,
    required this._logger,
    ThemeMode initialMode = ThemeMode.system,
  }) : _themeMode = initialMode;

  final KeyValueStore _store;
  final AppLogger _logger;

  ThemeMode _themeMode;

  /// 当前主题模式。
  ThemeMode get themeMode => _themeMode;

  /// 当前是否为深色模式（含跟随系统时的解析结果）。
  bool isDarkMode(BuildContext context) => switch (_themeMode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark,
  };

  /// 是否跟随系统。
  bool get followsSystem => _themeMode == ThemeMode.system;

  /// 设置主题模式。
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
    await _persist();
  }

  /// 在深色 / 浅色之间切换，用于设置页的开关。
  Future<void> setDarkMode(bool isDark) =>
      setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);

  /// 恢复跟随系统。
  Future<void> followSystem() => setThemeMode(ThemeMode.system);

  Future<void> _persist() async {
    try {
      await _store.writeString(StorageKeys.themeMode, _themeMode.name);
    } on Object catch (error, stackTrace) {
      // 写失败只影响"下次启动能否记住"，不该打断当前交互。
      _logger.w('主题设置保存失败', error, stackTrace);
    }
  }
}
