import 'package:chinese_textbooks/services/services.dart';

/// 内存键值存储。
///
/// `PreferencesStore` 要走平台通道，纯 Dart 测试里用不了。而书架的整理信息、
/// 阅读进度都要经过 [KeyValueStore]，没有这个替身就跑不通完整链路。
final class MemoryStore implements KeyValueStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> readString(String key) async => _data[key];

  @override
  Future<void> writeString(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<Set<String>> keys() async => _data.keys.toSet();
}
