import 'package:flutter/material.dart';

import '../services/logger/app_logger.dart';
import '../services/storage/key_value_store.dart';
import '../values/values.dart';

/// 语言状态。
///
/// [locale] 为 `null` 表示跟随系统，这也是默认行为——
/// 强制指定语言会让海外设备上的用户看到非母语界面。
final class AppLocaleProvider extends ChangeNotifier {
  AppLocaleProvider({
    required this._store,
    required this._logger,
    Locale? initialLocale,
  }) : _locale = initialLocale;

  /// 应用支持的语言。
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
  ];

  final KeyValueStore _store;
  final AppLogger _logger;

  Locale? _locale;

  /// 当前语言；`null` 表示跟随系统。
  Locale? get locale => _locale;

  /// 是否跟随系统。
  bool get followsSystem => _locale == null;

  /// 设置语言，传 `null` 表示跟随系统。
  Future<void> setLocale(Locale? locale) async {
    if (locale?.languageCode == _locale?.languageCode) {
      return;
    }
    _locale = locale;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final Locale? current = _locale;
      if (current == null) {
        await _store.delete(StorageKeys.locale);
      } else {
        await _store.writeString(StorageKeys.locale, current.languageCode);
      }
    } on Object catch (error, stackTrace) {
      _logger.w('语言设置保存失败', error, stackTrace);
    }
  }
}
