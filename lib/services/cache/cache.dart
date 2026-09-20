/// 缓存层。
///
/// 分层结构（自上而下）：
/// ```
/// CacheManager      门面：按业务语义读写，屏蔽全部细节
///   ├── CachePolicy         决策：读谁、写谁、存多久
///   ├── CacheCodec          编解码：值 ↔ 字符串
///   └── CacheStore          存储契约
///         ├── MemoryCacheStore        一级：进程内 LRU
///         ├── PreferencesCacheStore   二级：落盘持久化
///         └── TieredCacheStore        组合：多级串联 + 回填
/// ```
library;

export 'cache_codec.dart';
export 'cache_entry.dart';
export 'cache_key_builder.dart';
export 'cache_manager.dart';
export 'cache_policy.dart';
export 'cache_policy_registry.dart';
export 'cache_request.dart';
export 'cache_store.dart';
export 'memory_cache_store.dart';
export 'preferences_cache_store.dart';
export 'tiered_cache_store.dart';
