import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../utils/utils.dart';
import '../../../values/values.dart';
import '../../cache/cache.dart';
import '../../logger/app_logger.dart';

/// HTTP 缓存拦截器（装饰器模式）。
///
/// 它在**完全不改变调用方写法**的前提下，为请求附加了缓存能力：
/// 业务代码仍然只是 `dio.get(...)`，缓存与否由 [CachePolicy] 决定。
///
/// 执行时机与职责：
/// - `onRequest`：按策略决定"直接返回缓存"还是"继续走网络"，
///   并在需要时补上条件请求头（`If-None-Match` / `If-Modified-Since`）；
/// - `onResponse`：把成功响应写入缓存；处理 `304 Not Modified`；
/// - `onError`：网络失败时用陈旧缓存兜底，把"请求失败"变成"看到略旧的数据"。
///
/// 只处理 `GET` 请求。写操作（POST/PUT/PATCH/DELETE）缓存起来会产生
/// 严重的正确性问题，它们需要的是幂等键而不是缓存。
final class CacheInterceptor extends Interceptor {
  CacheInterceptor({
    required this._cache,
    required this._logger,
    required this._revalidationClient,
    required this._policyRegistry,
    this._keyBuilder = defaultCacheKeyBuilder,
  });

  final CacheManager _cache;
  final AppLogger _logger;

  /// 后台静默刷新所用的客户端。
  ///
  /// 与主客户端是同一个 `Dio` 实例，因此刷新请求同样会经过鉴权与日志拦截器。
  /// 刷新时会在 extra 上打 [CacheRequestKeys.bypassRead] 标记，
  /// 跳过"读缓存"阶段，否则刷新请求会命中自己，永远刷不出新数据。
  final Dio _revalidationClient;

  final CachePolicyRegistry _policyRegistry;
  final CacheKeyBuilder _keyBuilder;

  static const String _etagHeader = 'etag';
  static const String _lastModifiedHeader = 'last-modified';
  static const String _ifNoneMatchHeader = 'if-none-match';
  static const String _ifModifiedSinceHeader = 'if-modified-since';

  // ==================== 请求阶段 ====================

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isCacheable(options)) {
      handler.next(options);
      return;
    }

    // 解析策略：请求级显式指定 > 注册表的路径规则 > 默认不缓存。
    final CachePolicy policy =
        options.cachePolicy ?? _policyRegistry.resolve(options.path);
    options.cachePolicy = policy;

    if (!policy.readsCache) {
      handler.next(options);
      return;
    }

    final String key = _keyBuilder(options);
    options.extra[CacheRequestKeys.key] = key;

    // 后台刷新请求只写不读，否则会命中自己。
    if (options.extra[CacheRequestKeys.bypassRead] == true) {
      handler.next(options);
      return;
    }

    final CacheEntry? entry = await _cache.readEntry(key);
    if (entry == null) {
      if (policy.strategy == CacheStrategy.cacheOnly) {
        handler.reject(_cacheMiss(options, key), true);
        return;
      }
      handler.next(options);
      return;
    }

    switch (policy.strategy) {
      // 前面已按 readsCache 提前返回，这里列出只是为了满足穷尽性检查。
      case CacheStrategy.networkOnly:
        handler.next(options);

      case CacheStrategy.cacheOnly:
        _logger.t('缓存命中（cacheOnly）：$key');
        handler.resolve(_toResponse(entry, options));

      case CacheStrategy.cacheFirst:
        if (entry.isFresh) {
          _logger.t('缓存命中（cacheFirst）：$key');
          handler.resolve(_toResponse(entry, options));
        } else {
          handler.next(options);
        }

      case CacheStrategy.staleWhileRevalidate:
        if (entry.isUsableAsStale(policy.maxStale)) {
          _logger.t('返回陈旧缓存并触发后台刷新：$key');
          unawaited(_revalidate(options));
          handler.resolve(_toResponse(entry, options));
        } else {
          handler.next(options);
        }

      case CacheStrategy.networkFirst:
        // 网络优先。带上条件请求头，若服务端回 304 就省下一次响应体传输。
        _applyConditionalHeaders(options, entry);
        handler.next(options);
    }
  }

  // ==================== 响应阶段 ====================

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final RequestOptions options = response.requestOptions;
    final CachePolicy? policy = options.cachePolicy;
    final String? key = options.extra[CacheRequestKeys.key] as String?;

    if (policy == null || !policy.writesCache || key == null) {
      handler.next(response);
      return;
    }

    // 304：内容没变。延长有效期即可，不必重新下载响应体。
    if (response.statusCode == HttpStatus.notModified) {
      final CacheEntry? entry = await _cache.readEntry(key);
      if (entry == null) {
        handler.next(response);
        return;
      }
      final CacheEntry refreshed = _refresh(entry, policy, response);
      await _cache.writeEntry(refreshed, persist: policy.persist);
      _logger.d('304 命中，已延长缓存有效期：$key');
      handler.resolve(_toResponse(refreshed, options));
      return;
    }

    await _cache.writeEntry(
      _toEntry(key, response, policy),
      persist: policy.persist,
    );
    handler.next(response);
  }

  // ==================== 错误阶段 ====================

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final CachePolicy? policy = options.cachePolicy;
    final String? key = options.extra[CacheRequestKeys.key] as String?;

    // 用户主动取消不是失败，不该拿缓存去"补救"一个已经被放弃的请求。
    final bool canFallback =
        policy != null &&
        key != null &&
        err.type != DioExceptionType.cancel &&
        (policy.strategy == CacheStrategy.networkFirst ||
            policy.strategy == CacheStrategy.cacheFirst);

    if (!canFallback) {
      handler.next(err);
      return;
    }

    final CacheEntry? entry = await _cache.readEntry(key);
    if (entry == null || !entry.isUsableAsStale(policy.maxStale)) {
      handler.next(err);
      return;
    }

    _logger.i('请求失败，已降级为缓存数据：$key');
    handler.resolve(_toResponse(entry, options));
  }

  // ==================== 内部实现 ====================

  /// 该请求是否参与缓存。
  bool _isCacheable(RequestOptions options) {
    if (options.method.toUpperCase() != 'GET') {
      return false;
    }
    // 流式与二进制响应无法安全地转成字符串缓存。
    return options.responseType == ResponseType.json ||
        options.responseType == ResponseType.plain;
  }

  /// 用缓存条目构造响应。
  Response<dynamic> _toResponse(CacheEntry entry, RequestOptions options) {
    return Response<dynamic>(
      data: _decodePayload(entry.payload),
      requestOptions: options,
      statusCode: HttpStatus.ok,
      statusMessage: 'OK (from cache)',
    )..markServedFromCache(entry.createdAt);
  }

  /// 把成功响应转换成缓存条目。
  CacheEntry _toEntry(
    String key,
    Response<dynamic> response,
    CachePolicy policy,
  ) {
    final DateTime now = DateTime.now();
    return CacheEntry(
      key: key,
      payload: _encodePayload(response.data),
      createdAt: now,
      expiresAt: now.add(policy.ttl),
      lastAccessedAt: now,
      etag: response.headers.value(_etagHeader),
      lastModified: response.headers.value(_lastModifiedHeader),
    );
  }

  /// 依据 304 响应延长条目的有效期。
  ///
  /// `createdAt` 同步更新为当前时间：条目刚刚被服务端确认过，
  /// 保留期应当从这次校验重新起算，否则长期被校验的条目仍会被误清理。
  CacheEntry _refresh(
    CacheEntry entry,
    CachePolicy policy,
    Response<dynamic> response,
  ) {
    final DateTime now = DateTime.now();
    return CacheEntry(
      key: entry.key,
      payload: entry.payload,
      createdAt: now,
      expiresAt: now.add(policy.ttl),
      lastAccessedAt: now,
      etag: response.headers.value(_etagHeader) ?? entry.etag,
      lastModified:
          response.headers.value(_lastModifiedHeader) ?? entry.lastModified,
      metadata: entry.metadata,
    );
  }

  /// 补上条件请求头，并放开对 304 的状态码校验。
  void _applyConditionalHeaders(RequestOptions options, CacheEntry entry) {
    final String? etag = entry.etag;
    final String? lastModified = entry.lastModified;
    if (etag == null && lastModified == null) {
      return;
    }
    if (etag != null) {
      options.headers[_ifNoneMatchHeader] = etag;
    }
    if (lastModified != null) {
      options.headers[_ifModifiedSinceHeader] = lastModified;
    }
    // dio 默认只把 2xx 视为成功，304 会被抛成异常，这里显式放行。
    options.validateStatus = _acceptNotModified;
  }

  static bool _acceptNotModified(int? status) {
    if (status == null) {
      return false;
    }
    return (status >= 200 && status < 300) || status == HttpStatus.notModified;
  }

  /// 后台静默刷新。
  ///
  /// 失败只记日志：用户此刻看到的已经是可用数据，刷新失败不该产生任何打扰。
  Future<void> _revalidate(RequestOptions options) async {
    try {
      await _revalidationClient.fetch<dynamic>(
        options.copyWith(
          extra: <String, dynamic>{
            ...options.extra,
            CacheRequestKeys.bypassRead: true,
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger.d('后台刷新失败：${options.uri}', error, stackTrace);
    }
  }

  /// 缓存未命中且策略要求必须有缓存时的错误。
  DioException _cacheMiss(RequestOptions options, String key) => DioException(
    requestOptions: options,
    type: DioExceptionType.unknown,
    error: CacheFailure(message: AppStrings.errorCache, cause: '未命中缓存：$key'),
  );

  String _encodePayload(Object? data) =>
      data is String ? data : jsonEncode(data);

  Object? _decodePayload(String payload) {
    try {
      return jsonDecode(payload);
    } on FormatException {
      // 非 JSON 响应（如纯文本），原样返回。
      return payload;
    }
  }
}
