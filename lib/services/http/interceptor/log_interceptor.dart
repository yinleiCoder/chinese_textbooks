import 'package:dio/dio.dart';

import '../../../utils/utils.dart';
import '../../cache/cache_request.dart';
import '../../logger/app_logger.dart';

/// 请求日志拦截器。
///
/// 职责边界：**只记录，不修改**。任何改写请求/响应的逻辑都不应该放在这里，
/// 否则日志看到的内容与实际发出的内容就会不一致，失去排查价值。
///
/// 安全约束：`Authorization` / `Cookie` 等凭据类请求头会被打码后再输出，
/// 避免令牌被完整写进日志文件或控制台。
final class AppLogInterceptor extends Interceptor {
  AppLogInterceptor({required this._logger});

  final AppLogger _logger;

  /// 需要打码的请求头。
  static const Set<String> _sensitiveHeaders = <String>{
    'authorization',
    'cookie',
    'set-cookie',
    'proxy-authorization',
  };

  /// 日志中响应体的最大长度，超出部分截断。
  static const int _maxBodyLength = 800;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.d(
      '→ ${options.method} ${options.uri}\n'
      'headers: ${_sanitizeHeaders(options.headers)}\n'
      'body: ${_preview(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final bool fromCache = response.isServedFromCache;
    _logger.d(
      '← ${response.statusCode} ${response.requestOptions.uri}'
      '${fromCache ? ' [缓存命中]' : ''}\n'
      'body: ${_preview(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.e(
      '✗ ${err.requestOptions.method} ${err.requestOptions.uri} (${err.type.name})',
      err.error ?? err.message,
      err.stackTrace,
    );
    handler.next(err);
  }

  /// 复制请求头并对敏感字段打码。
  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    return <String, dynamic>{
      for (final MapEntry<String, dynamic> entry in headers.entries)
        entry.key: _sensitiveHeaders.contains(entry.key.toLowerCase())
            ? '***'
            : entry.value,
    };
  }

  /// 生成可读的报文预览。
  String _preview(Object? data) {
    if (data == null) {
      return '(空)';
    }
    return data.toString().truncate(_maxBodyLength);
  }
}
