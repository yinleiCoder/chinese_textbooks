import 'cache_entry.dart';

/// 缓存存储抽象（策略模式的抽象策略）。
///
/// 所有实现都必须满足两条契约：
/// 1. **读操作永不抛异常**——缓存是尽力而为的旁路，读不到就返回 `null`，
///    实现内部出错时记录日志并降级，绝不能把异常抛给业务流程；
/// 2. **`read` 返回过期条目**——新鲜度判断由调用方（`CacheManager`）负责，
///    因为离线兜底与 `staleWhileRevalidate` 恰恰需要读到过期数据。
///
/// 现有实现：
/// - `MemoryCacheStore`：进程内 LRU，一级缓存；
/// - `PreferencesCacheStore`：落盘持久化，二级缓存；
/// - `TieredCacheStore`：把上面两者组合成多级缓存。
abstract interface class CacheStore {
  /// 存储名称，用于日志与调试。
  String get name;

  /// 读取条目，不存在或读取失败时返回 `null`。
  ///
  /// 返回的条目**可能已过期**，调用方需自行判断 [CacheEntry.isFresh]。
  Future<CacheEntry?> read(String key);

  /// 写入条目，键相同则覆盖。
  ///
  /// 写入失败时静默降级（记录日志），不向调用方抛出异常。
  Future<void> write(CacheEntry entry);

  /// 删除单个条目，键不存在时静默返回。
  Future<void> delete(String key);

  /// 列出全部键。
  Future<Set<String>> keys();

  /// 清空本存储的全部数据。
  Future<void> clear();

  /// 清理超过 [retention] 未被写入的条目，返回清理数量。
  ///
  /// 各实现可以在容量溢出时顺带调用它，避免过期数据长期占用空间。
  Future<int> evictExpired({required Duration retention});
}
