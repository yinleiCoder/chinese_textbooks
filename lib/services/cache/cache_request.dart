import 'package:dio/dio.dart';

import 'cache_policy.dart';

/// `RequestOptions.extra` / `Response.extra` 中与缓存相关的键。
///
/// 统一用 `cache:` 前缀，避免与业务自定义的 extra 键冲突。
abstract final class CacheRequestKeys {
  /// 本次请求使用的 [CachePolicy]。
  static const String policy = 'cache:policy';

  /// 缓存身份标识，用于区分不同用户/租户的同一接口。
  static const String identity = 'cache:identity';

  /// 标记该响应直接来自缓存（未发起真实网络请求）。
  static const String servedFromCache = 'cache:servedFromCache';

  /// 该响应所对应缓存条目的写入时间。
  static const String cachedAt = 'cache:cachedAt';

  /// 本次请求解析出的缓存键。
  ///
  /// 由 `CacheInterceptor` 在 `onRequest` 阶段写入，
  /// 供 `onResponse` / `onError` 阶段直接复用，避免重复计算。
  static const String key = 'cache:key';

  /// 跳过"读缓存"阶段，但**仍然写缓存**。
  ///
  /// 后台静默刷新（stale-while-revalidate）依赖这个标记：
  /// 刷新请求不能再读一次缓存，否则会自己命中自己，永远刷新不了。
  static const String bypassRead = 'cache:bypassRead';
}

/// 在请求上读写缓存配置的便捷扩展。
///
/// 业务侧发起请求时只需：
/// ```dart
/// dio.get<List<Textbook>>(
///   ApiEndpoints.textbooks,
///   options: Options(extra: <String, dynamic>{
///     CacheRequestKeys.policy: CachePolicy.longLived,
///   }),
/// );
/// ```
extension CacheRequestOptionsX on RequestOptions {
  /// 本次请求显式指定的缓存策略，未指定时为 `null`。
  ///
  /// 显式指定的优先级高于 `CachePolicyRegistry` 中的路径规则。
  CachePolicy? get cachePolicy =>
      extra[CacheRequestKeys.policy] as CachePolicy?;

  /// 设置本次请求的缓存策略。
  set cachePolicy(CachePolicy? policy) {
    if (policy == null) {
      extra.remove(CacheRequestKeys.policy);
    } else {
      extra[CacheRequestKeys.policy] = policy;
    }
  }

  /// 缓存身份标识。
  ///
  /// 默认 `anonymous`。登录后应当置为当前用户 ID，
  /// 否则会出现"A 用户看到 B 用户数据"的串号问题。
  String get cacheIdentity =>
      extra[CacheRequestKeys.identity] as String? ?? 'anonymous';

  /// 设置缓存身份标识。
  set cacheIdentity(String identity) {
    extra[CacheRequestKeys.identity] = identity;
  }
}

/// 判断响应来源的扩展。
extension CacheResponseX on Response<dynamic> {
  /// 该响应是否直接由缓存返回（没有发起真实网络请求）。
  ///
  /// UI 可以据此展示"离线数据"角标。
  bool get isServedFromCache => extra[CacheRequestKeys.servedFromCache] == true;

  /// 该响应所对应缓存条目的写入时间。
  DateTime? get cachedAt => extra[CacheRequestKeys.cachedAt] as DateTime?;

  /// 打上"来自缓存"的标记。
  ///
  /// 返回自身以便链式调用。
  Response<dynamic> markServedFromCache(DateTime cachedAt) {
    extra[CacheRequestKeys.servedFromCache] = true;
    extra[CacheRequestKeys.cachedAt] = cachedAt;
    return this;
  }
}
