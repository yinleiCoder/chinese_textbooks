import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_value_store.dart';

/// 基于系统安全存储的键值存储实现。
///
/// 用于**必须加密**的少量数据：登录令牌、刷新令牌、设备指纹等。
/// 不要拿它当普通缓存用——安全存储的每次读写都要走平台通道，
/// 开销远高于 `shared_preferences`，且容量有限。
///
/// 平台差异：
/// - Android：Keystore 加密后写入 SharedPreferences；
/// - iOS / macOS：写入 Keychain；
/// - Windows / Linux：依赖各自的凭据服务，桌面端可能不可用，
///   因此调用方必须处理 [Exception]（本类的读操作失败会向上抛出，
///   由 `Result.guard` 统一收拢）。
final class SecureStore implements KeyValueStore {
  SecureStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readString(String key) => _storage.read(key: key);

  @override
  Future<void> writeString(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();

  @override
  Future<Set<String>> keys() async {
    final Map<String, String> all = await _storage.readAll();
    return all.keys.toSet();
  }
}
