import 'cache_entry.dart';
import 'cache_store.dart';

/// 多级缓存（组合模式）。
///
/// 把若干个 [CacheStore] 按"由快到慢"的顺序串成一条链，
/// 对上仍然表现为**一个** [CacheStore]，调用方无需感知层级的存在。
///
/// 读写策略：
/// - **读**：从第一级开始逐级向下查找，命中后把条目**回填**到它上面的所有层级。
///   回填是分级缓存的核心收益——第二次访问同一份数据时，第一级就能命中；
/// - **写**：写穿（write-through）到每一级，保证内存与磁盘视图一致；
/// - **删/清空**：所有层级一起执行，避免出现"内存已失效但磁盘还能读到"的脏读。
///
/// 典型组合：`TieredCacheStore([MemoryCacheStore(), PreferencesCacheStore()])`。
final class TieredCacheStore implements CacheStore {
  TieredCacheStore(this._levels) : assert(_levels.isNotEmpty, '至少需要一级缓存');

  /// 层级列表，索引越小越快。
  final List<CacheStore> _levels;

  @override
  String get name =>
      'tiered(${_levels.map((CacheStore level) => level.name).join(' > ')})';

  @override
  Future<CacheEntry?> read(String key) async {
    for (int index = 0; index < _levels.length; index++) {
      final CacheEntry? entry = await _levels[index].read(key);
      if (entry == null) {
        continue;
      }
      await _backfill(upperLevels: index, entry: entry);
      return entry;
    }
    return null;
  }

  @override
  Future<void> write(CacheEntry entry) async {
    for (final CacheStore level in _levels) {
      await level.write(entry);
    }
  }

  @override
  Future<void> delete(String key) async {
    for (final CacheStore level in _levels) {
      await level.delete(key);
    }
  }

  @override
  Future<Set<String>> keys() async {
    // 以最慢的一级为准，它保存的是全集。
    return _levels.last.keys();
  }

  @override
  Future<void> clear() async {
    for (final CacheStore level in _levels) {
      await level.clear();
    }
  }

  @override
  Future<int> evictExpired({required Duration retention}) async {
    int removed = 0;
    for (final CacheStore level in _levels) {
      removed += await level.evictExpired(retention: retention);
    }
    return removed;
  }

  /// 把命中条目回填到 [upperLevels] 个上层缓存中。
  Future<void> _backfill({
    required int upperLevels,
    required CacheEntry entry,
  }) async {
    for (int index = 0; index < upperLevels; index++) {
      await _levels[index].write(entry);
    }
  }
}
