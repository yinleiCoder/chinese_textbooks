import 'dart:async';

import '../../utils/utils.dart';
import '../../values/values.dart';
import '../logger/app_logger.dart';
import 'cache_codec.dart';
import 'cache_entry.dart';
import 'cache_policy.dart';
import 'cache_store.dart';

/// 缓存门面（Facade）。
///
/// 对上层提供"按业务语义读写缓存"的统一入口，屏蔽掉键构造、编解码、
/// 新鲜度判断、多级路由这些细节。四个协作对象各司其职：
///
/// | 角色 | 类型 | 职责 |
/// | --- | --- | --- |
/// | 抽象策略 | [CacheStore] | 定义存储契约 |
/// | 具体策略 | `MemoryCacheStore` / `PreferencesCacheStore` | 内存 LRU / 落盘 |
/// | 组合 | `TieredCacheStore` | 多级缓存串联与回填 |
/// | 编解码策略 | [CacheCodec] | 值 ↔ 字符串 |
/// | 决策策略 | [CachePolicy] | 读谁、写谁、存多久 |
/// | 门面 | **本类** | 串起以上全部，对外只暴露业务语义 |
///
/// **失败语义**：缓存的任何异常都不会向上抛出。缓存是旁路，
/// 它坏掉最多让应用变慢，绝不能让功能不可用。唯一的例外是
/// [load] 中 `cacheOnly` 策略未命中——此时缓存是唯一数据源，
/// 必须让调用方感知失败。
final class CacheManager {
  CacheManager({
    required this._store,
    required this._logger,
    this._transientStore,
    this.retention = AppConfig.cacheRetention,
  });

  /// 默认存储，通常是一个 `TieredCacheStore`（内存 + 磁盘）。
  final CacheStore _store;

  /// 仅内存的存储，供 `persist: false` 的策略使用。
  ///
  /// 与 [_store] 的第一级应当是**同一个实例**，这样写入内存的条目
  /// 依然能被常规读取路径命中。留空则退化为"总是写默认存储"。
  final CacheStore? _transientStore;

  final AppLogger _logger;

  /// 条目保留期：写入时间早于 `now - retention` 的条目会被物理删除。
  final Duration retention;

  /// 底层存储名称，用于调试与日志。
  String get storeName => _store.name;

  // ==================== 读 ====================

  /// 读取原始条目（不做新鲜度判断，也不解码）。
  ///
  /// 供 HTTP 缓存拦截器使用——它需要拿到 [CacheEntry] 上的响应头信息。
  Future<CacheEntry?> readEntry(String key) => _store.read(key);

  /// 读取并解码。
  ///
  /// [allowStale] 为 `true` 时允许返回过期但仍在 [maxStale] 之内的数据，
  /// 这是断网降级的关键。
  Future<T?> read<T>(
    String key, {
    required CacheCodec<T> codec,
    bool allowStale = false,
    Duration? maxStale,
  }) async {
    final CacheEntry? entry = await _store.read(key);
    if (entry == null) {
      return null;
    }
    final bool usable =
        entry.isFresh || (allowStale && entry.isUsableAsStale(maxStale));
    if (!usable) {
      _logger.t('缓存命中但不可用（${entry.isFresh ? '新鲜' : '过期'}）：$key');
      return null;
    }
    _logger.t('缓存命中：$key');
    return _decode(entry, codec);
  }

  // ==================== 写 ====================

  /// 编码并写入缓存。
  ///
  /// [persist] 为 `false` 时只写内存，不落盘。
  Future<void> write<T>(
    String key,
    T value, {
    required CacheCodec<T> codec,
    Duration? ttl,
    bool persist = true,
  }) async {
    final String payload;
    try {
      payload = codec.encode(value);
    } on Object catch (error, stackTrace) {
      // 编码失败通常是实体没实现好序列化，属于开发期问题，需要明确的日志。
      _logger.w('缓存编码失败，已跳过写入：$key', error, stackTrace);
      return;
    }
    final DateTime now = DateTime.now();
    await writeEntry(
      CacheEntry(
        key: key,
        payload: payload,
        createdAt: now,
        expiresAt: now.add(ttl ?? CachePolicy.standard.ttl),
        lastAccessedAt: now,
      ),
      persist: persist,
    );
  }

  /// 写入一个已经构造好的条目。
  ///
  /// HTTP 缓存拦截器在拿到响应后走这条路径，因为它需要携带 ETag 等元数据。
  Future<void> writeEntry(CacheEntry entry, {bool persist = true}) async {
    final CacheStore target = persist ? _store : (_transientStore ?? _store);
    await target.write(entry);
  }

  // ==================== 按策略加载 ====================

  /// 按 [policy] 决策如何取得数据，是缓存层对外的主入口。
  ///
  /// 五种策略的行为见 [CacheStrategy] 的文档。这里体现的是**决策逻辑**
  /// 本身与数据来源无关——它既能包装 HTTP 请求，也能包装数据库查询
  /// 或一次昂贵的本地计算。
  Future<Result<T>> load<T>({
    required String key,
    required CacheCodec<T> codec,
    required Future<T> Function() loader,
    CachePolicy policy = CachePolicy.standard,
  }) async {
    switch (policy.strategy) {
      case CacheStrategy.networkOnly:
        return _fetch(key: key, codec: codec, loader: loader, policy: policy);

      case CacheStrategy.cacheOnly:
        final T? cached = await read(
          key,
          codec: codec,
          allowStale: true,
          maxStale: policy.maxStale,
        );
        return cached != null
            ? Success<T>(cached)
            : Failure<T>(
                CacheFailure(
                  message: AppStrings.errorCache,
                  cause: 'cacheOnly 未命中：$key',
                ),
              );

      case CacheStrategy.cacheFirst:
        // 缓存优先只认新鲜数据：陈旧内容直接走网络，避免"看起来更快但内容过期"。
        final T? fresh = await read(key, codec: codec);
        if (fresh != null) {
          return Success<T>(fresh);
        }
        return _fetch(key: key, codec: codec, loader: loader, policy: policy);

      case CacheStrategy.networkFirst:
        final Result<T> result = await _fetch(
          key: key,
          codec: codec,
          loader: loader,
          policy: policy,
        );
        if (result.isSuccess) {
          return result;
        }
        // 网络失败时用陈旧数据兜底，兜底也没有才把原始错误抛给上层。
        final T? stale = await read(
          key,
          codec: codec,
          allowStale: true,
          maxStale: policy.maxStale,
        );
        if (stale != null) {
          _logger.i('网络失败，已降级为缓存数据：$key');
          return Success<T>(stale);
        }
        return result;

      case CacheStrategy.staleWhileRevalidate:
        final CacheEntry? entry = await readEntry(key);
        if (entry == null || !entry.isUsableAsStale(policy.maxStale)) {
          return _fetch(key: key, codec: codec, loader: loader, policy: policy);
        }
        final T? cached = _decode(entry, codec);
        if (cached == null) {
          return _fetch(key: key, codec: codec, loader: loader, policy: policy);
        }
        // 仍然新鲜的条目无需多此一举，只有过期了才需要后台刷新。
        // 刷新结果不等待，供下一次访问使用。
        if (entry.isExpired) {
          unawaited(
            _fetch(key: key, codec: codec, loader: loader, policy: policy),
          );
        }
        return Success<T>(cached);
    }
  }

  // ==================== 失效 ====================

  /// 删除单个键。
  Future<void> invalidate(String key) => _store.delete(key);

  /// 按条件批量失效。
  ///
  /// 例如登出时清理某个用户相关的全部缓存：
  /// ```dart
  /// await cache.invalidateWhere((key) => key.endsWith('#$userId'));
  /// ```
  Future<int> invalidateWhere(bool Function(String key) test) async {
    final Set<String> all = await _store.keys();
    final List<String> targets = all.where(test).toList(growable: false);
    for (final String key in targets) {
      await _store.delete(key);
    }
    return targets.length;
  }

  /// 清空全部缓存。
  Future<void> clear() => _store.clear();

  /// 按 [retention] 清理长期未写入的条目，返回清理数量。
  Future<int> evictExpired() => _store.evictExpired(retention: retention);

  /// 列出当前所有缓存键，供调试页展示。
  Future<Set<String>> keys() => _store.keys();

  // ==================== 内部实现 ====================

  /// 真正执行加载并在成功后回写缓存。
  Future<Result<T>> _fetch<T>({
    required String key,
    required CacheCodec<T> codec,
    required Future<T> Function() loader,
    required CachePolicy policy,
  }) async {
    final Result<T> result = await Result.guard(
      loader,
      onError: (Object error, StackTrace stackTrace) => UnknownFailure(
        message: AppStrings.errorUnknown,
        cause: error,
        stackTrace: stackTrace,
      ),
    );

    if (policy.writesCache && result is Success<T>) {
      await write(
        key,
        result.data,
        codec: codec,
        ttl: policy.ttl,
        persist: policy.persist,
      );
    }
    return result;
  }

  /// 解码，失败时清理脏数据并按未命中处理。
  T? _decode<T>(CacheEntry entry, CacheCodec<T> codec) {
    try {
      return codec.decode(entry.payload);
    } on Object catch (error, stackTrace) {
      _logger.w('缓存解码失败，已清理：${entry.key}', error, stackTrace);
      unawaited(_store.delete(entry.key));
      return null;
    }
  }
}
