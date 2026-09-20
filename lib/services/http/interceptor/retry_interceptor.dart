import 'dart:async';

import 'package:dio/dio.dart';

import '../../logger/app_logger.dart';

/// 自动重试拦截器。
///
/// 两条安全约束，缺一不可：
///
/// 1. **只重试幂等请求**。GET/HEAD/PUT/DELETE/OPTIONS 重复执行不改变服务端状态；
///    POST 则不然——超时后重试可能造成重复下单、重复提交作业，
///    这类"请求其实成功了但响应丢了"的场景必须交给业务侧用幂等键处理。
/// 2. **只重试可恢复的错误**。连接类错误与 5xx 值得重试；
///    4xx 是请求本身有问题，重试多少次都一样，只会拖慢错误反馈。
///
/// 退避采用指数增长（`backoff * 2^(n-1)`），避免服务端刚抖动就被重试请求打满。
final class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this._logger,
    required this._client,
    this.maxRetries = 2,
    this.backoff = const Duration(milliseconds: 400),
  });

  final AppLogger _logger;

  /// 用于重新发起请求的客户端。
  ///
  /// 直接复用创建它的 `Dio` 实例，因此重试会**重新走一遍完整的拦截器链**，
  /// 从而拿到最新的令牌、并正常写入缓存。
  final Dio _client;

  /// 最大重试次数（不含首次请求）。
  final int maxRetries;

  /// 退避基数。
  final Duration backoff;

  /// 记录当前请求已重试次数的 extra 键。
  static const String _attemptKey = 'http:retryAttempt';

  /// 允许重试的幂等 HTTP 方法。
  static const Set<String> _idempotentMethods = <String>{
    'GET',
    'HEAD',
    'PUT',
    'DELETE',
    'OPTIONS',
  };

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final int attempt = (options.extra[_attemptKey] as int? ?? 0) + 1;

    if (!_shouldRetry(err) || attempt > maxRetries) {
      handler.next(err);
      return;
    }

    // 指数退避：第 1 次等 backoff，第 2 次等 2*backoff，依此类推。
    final Duration delay = backoff * (1 << (attempt - 1));
    _logger.w(
      '请求失败，${delay.inMilliseconds}ms 后重试 '
      '（第 $attempt/$maxRetries 次）：${options.uri}',
    );
    await Future<void>.delayed(delay);

    try {
      final Response<dynamic> response = await _client.fetch<dynamic>(
        options..extra[_attemptKey] = attempt,
      );
      handler.resolve(response);
    } on DioException catch (retryError) {
      // 重试仍然失败：把最新的错误交给上层，
      // 它的 extra 里带着递增后的 attempt，因此不会再被无限重试。
      handler.next(retryError);
    }
  }

  /// 判断该错误是否值得重试。
  bool _shouldRetry(DioException err) {
    if (!_idempotentMethods.contains(err.requestOptions.method.toUpperCase())) {
      return false;
    }
    return switch (err.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => true,
      // 5xx 视为服务端临时故障；4xx 是请求本身的问题，重试无意义。
      DioExceptionType.badResponse => (err.response?.statusCode ?? 0) >= 500,
      DioExceptionType.badCertificate || DioExceptionType.cancel => false,
      // unknown 无法判断根因，保守起见不重试。
      DioExceptionType.unknown => false,
    };
  }
}
