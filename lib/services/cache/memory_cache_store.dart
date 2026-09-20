import 'dart:collection';

import '../../values/values.dart';
import 'cache_entry.dart';
import 'cache_store.dart';

/// 进程内一级缓存，采用 **LRU（最近最少使用）** 淘汰策略。
///
/// 为什么用 [LinkedHashMap]：
/// Dart 的 `LinkedHashMap` 在保持哈希表 O(1) 查找的同时维护了一条插入顺序链表。
/// 每次读取时先 `remove` 再 `[]=`，等价于把该键**移到链表尾部**，
/// 于是链表头部天然就是"最久未被使用"的条目，淘汰时取 `keys.first` 即可，
/// 无需自己维护双向链表或时间戳排序。
///
/// 接口是异步的，是为了和 [CacheStore] 的其他实现保持一致的调用形态；
/// 本实现的每个方法体内部都是同步完成的。
final class MemoryCacheStore implements CacheStore {
  MemoryCacheStore({this.capacity = AppConfig.memoryCacheCapacity}) {
    assert(capacity > 0, 'capacity 必须为正数');
  }

  /// 条目数量上限，超出后按 LRU 淘汰。
  final int capacity;

  /// 按访问顺序排列的条目，头部最旧、尾部最新。
  final LinkedHashMap<String, CacheEntry> _entries =
      LinkedHashMap<String, CacheEntry>();

  @override
  String get name => 'memory($capacity)';

  @override
  Future<CacheEntry?> read(String key) async {
    final CacheEntry? entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    // 重新插回尾部，标记为最近使用。
    final CacheEntry touched = entry.touched();
    _entries[key] = touched;
    return touched;
  }

  @override
  Future<void> write(CacheEntry entry) async {
    // 先删后插，保证被覆盖的键也移动到尾部。
    _entries
      ..remove(entry.key)
      ..[entry.key] = entry;
    _evictOverflow();
  }

  @override
  Future<void> delete(String key) async => _entries.remove(key);

  @override
  Future<Set<String>> keys() async => _entries.keys.toSet();

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<int> evictExpired({required Duration retention}) async {
    final DateTime threshold = DateTime.now().subtract(retention);
    final List<String> stale = _entries.entries
        .where(
          (MapEntry<String, CacheEntry> e) =>
              e.value.createdAt.isBefore(threshold),
        )
        .map((MapEntry<String, CacheEntry> e) => e.key)
        .toList(growable: false);
    for (final String key in stale) {
      _entries.remove(key);
    }
    return stale.length;
  }

  /// 容量溢出时淘汰，先清过期条目，再按 LRU 淘汰。
  void _evictOverflow() {
    if (_entries.length <= capacity) {
      return;
    }
    final DateTime now = DateTime.now();
    _entries.removeWhere(
      (String _, CacheEntry entry) => entry.expiresAt.isBefore(now),
    );
    while (_entries.length > capacity) {
      // keys.first 即最久未被访问的键。
      _entries.remove(_entries.keys.first);
    }
  }
}
