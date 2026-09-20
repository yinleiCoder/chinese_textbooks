import 'dart:async';
import 'dart:convert';

import '../../values/values.dart';
import '../logger/app_logger.dart';
import '../storage/key_value_store.dart';
import 'cache_entry.dart';
import 'cache_store.dart';

/// 基于 [KeyValueStore] 的持久化二级缓存。
///
/// 条目以 JSON 字符串落盘，键名由注入的 [KeyValueStore] 负责加前缀隔离，
/// 因此本类不需要再关心命名空间问题。
///
/// 容量控制：写入后若条目数超过 [capacity]，按 [CacheEntry.lastAccessedAt]
/// 从旧到新淘汰。这一步需要读取全部条目，代价较高，因此只在**确实溢出**时执行。
final class PreferencesCacheStore implements CacheStore {
  PreferencesCacheStore({
    required this._store,
    required this._logger,
    this.capacity = AppConfig.persistentCacheCapacity,
  }) {
    assert(capacity > 0, 'capacity 必须为正数');
  }

  final KeyValueStore _store;
  final AppLogger _logger;

  /// 条目数量上限。
  final int capacity;

  @override
  String get name => 'persistent($capacity)';

  @override
  Future<CacheEntry?> read(String key) async {
    try {
      final String? raw = await _store.readString(key);
      if (raw == null) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        // 数据被外部篡改或版本不兼容，直接丢弃，避免反复报错。
        _logger.w('缓存条目结构非法，已丢弃：$key');
        await _store.delete(key);
        return null;
      }
      final CacheEntry entry = CacheEntry.fromJson(decoded).touched();
      // 异步回写访问时间，不阻塞读取路径。
      unawaited(_persistAccessTime(key, entry));
      return entry;
    } on Object catch (error, stackTrace) {
      _logger.w('读取缓存失败：$key', error, stackTrace);
      return null;
    }
  }

  @override
  Future<void> write(CacheEntry entry) async {
    try {
      await _store.writeString(entry.key, jsonEncode(entry.toJson()));
      await _evictOverflow();
    } on Object catch (error, stackTrace) {
      _logger.w('写入缓存失败：${entry.key}', error, stackTrace);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _store.delete(key);
    } on Object catch (error, stackTrace) {
      _logger.w('删除缓存失败：$key', error, stackTrace);
    }
  }

  @override
  Future<Set<String>> keys() async {
    try {
      return await _store.keys();
    } on Object catch (error, stackTrace) {
      _logger.w('枚举缓存键失败', error, stackTrace);
      return <String>{};
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _store.deleteAll();
    } on Object catch (error, stackTrace) {
      _logger.w('清空缓存失败', error, stackTrace);
    }
  }

  @override
  Future<int> evictExpired({required Duration retention}) async {
    final DateTime threshold = DateTime.now().subtract(retention);
    final Set<String> all = await keys();
    int removed = 0;
    for (final String key in all) {
      final CacheEntry? entry = await _readWithoutTouching(key);
      if (entry != null && entry.createdAt.isBefore(threshold)) {
        await delete(key);
        removed++;
      }
    }
    return removed;
  }

  /// 读取条目但不刷新访问时间，供内部淘汰逻辑使用。
  Future<CacheEntry?> _readWithoutTouching(String key) async {
    final String? raw = await _store.readString(key);
    if (raw == null) {
      return null;
    }
    final Object? decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? CacheEntry.fromJson(decoded)
        : null;
  }

  /// 把访问时间回写到磁盘。
  ///
  /// 单独抽出来是为了让 [read] 不必等待二次写入——读取路径应当尽快返回。
  Future<void> _persistAccessTime(String key, CacheEntry entry) async {
    try {
      await _store.writeString(key, jsonEncode(entry.toJson()));
    } on Object catch (_) {
      // 回写失败不影响本次读取结果，忽略即可。
    }
  }

  /// 超出容量时按最近访问时间淘汰最旧的一批。
  Future<void> _evictOverflow() async {
    final Set<String> all = await keys();
    if (all.length <= capacity) {
      return;
    }
    final List<CacheEntry> entries = <CacheEntry>[];
    for (final String key in all) {
      final CacheEntry? entry = await _readWithoutTouching(key);
      if (entry != null) {
        entries.add(entry);
      }
    }
    entries.sort((CacheEntry a, CacheEntry b) {
      final DateTime aTime = a.lastAccessedAt ?? a.createdAt;
      final DateTime bTime = b.lastAccessedAt ?? b.createdAt;
      return aTime.compareTo(bTime);
    });
    final int overflow = entries.length - capacity;
    for (final CacheEntry entry in entries.take(overflow)) {
      await delete(entry.key);
    }
    _logger.d('持久化缓存超限，已淘汰 $overflow 条');
  }
}
