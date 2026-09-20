import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// 基于 `shared_preferences` 的键值存储实现。
///
/// 命名空间由本类统一处理：外部传入的是**业务键**，
/// 内部自动补上 [prefix] 后再落盘。这样带来两个好处：
/// 1. 多个模块可以共用一个 `SharedPreferences` 而不会键名冲突；
/// 2. [deleteAll] 只会删掉自己前缀下的数据，不会误清别人的。
///
/// 使用 `SharedPreferencesAsync`（而非旧的 `SharedPreferences.getInstance()`）
/// 是官方推荐的新 API：无全局单例缓存，读写语义与底层存储完全一致。
final class PreferencesStore implements KeyValueStore {
  PreferencesStore({this.prefix = '', SharedPreferencesAsync? preferences})
    : assert(
        prefix == '' || prefix.endsWith(':'),
        'prefix 应以 : 结尾（如 "cache:"），避免 "app" 与 "app2" 这类前缀互相误伤',
      ),
      _preferences = preferences ?? SharedPreferencesAsync();

  /// 键前缀，形如 `cache:`。
  final String prefix;

  final SharedPreferencesAsync _preferences;

  String _namespaced(String key) => '$prefix$key';

  @override
  Future<String?> readString(String key) =>
      _preferences.getString(_namespaced(key));

  @override
  Future<void> writeString(String key, String value) =>
      _preferences.setString(_namespaced(key), value);

  @override
  Future<bool> containsKey(String key) =>
      _preferences.containsKey(_namespaced(key));

  @override
  Future<void> delete(String key) => _preferences.remove(_namespaced(key));

  @override
  Future<void> deleteAll() async {
    final Set<String> owned = await keys();
    await Future.wait(
      owned.map((String key) => _preferences.remove(_namespaced(key))),
    );
  }

  @override
  Future<Set<String>> keys() async {
    final Set<String> all = await _preferences.getKeys();
    if (prefix.isEmpty) {
      return all;
    }
    return all
        .where((String key) => key.startsWith(prefix))
        .map((String key) => key.substring(prefix.length))
        .toSet();
  }
}
