import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/utils.dart';
import '../../values/values.dart';

/// 从响应体中提取服务端错误文案。
typedef ServerMessageExtractor = String? Function(Object? responseData);

/// 把 [DioException] 翻译成 [AppFailure]。
///
/// 抽成接口是为了让上层（`ApiClient`）依赖抽象而非具体映射规则：
/// 测试时可以注入一个"永远返回固定失败"的实现，
/// 将来后端换了错误码规范也只需替换实现。
abstract interface class FailureMapper {
  /// 执行映射。
  AppFailure map(DioException exception);
}

/// 默认映射规则。
///
/// 编排原则：**先看传输层错误类型，再看 HTTP 状态码，最后看业务响应体**。
/// 顺序不能颠倒——超时可能压根没拿到响应，此时看状态码没有意义。
final class DefaultFailureMapper implements FailureMapper {
  const DefaultFailureMapper({
    this.extractServerMessage = defaultServerMessage,
  });

  /// 服务端错误文案提取器。
  ///
  /// 若后端在错误响应里带了更具体的提示（如"该手机号已注册"），
  /// 优先展示它，比统一的"请求有误"更有帮助。
  final ServerMessageExtractor extractServerMessage;

  @override
  AppFailure map(DioException exception) => switch (exception.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => NetworkFailure(
      message: AppStrings.errorTimeout,
      isTimeout: true,
      cause: exception,
      stackTrace: exception.stackTrace,
    ),

    DioExceptionType.connectionError => NetworkFailure(
      message: AppStrings.errorNetwork,
      cause: exception,
      stackTrace: exception.stackTrace,
    ),

    DioExceptionType.badCertificate => NetworkFailure(
      message: AppStrings.errorNetwork,
      cause: exception,
      stackTrace: exception.stackTrace,
    ),

    DioExceptionType.cancel => CancelledFailure(
      message: AppStrings.cancel,
      cause: exception,
      stackTrace: exception.stackTrace,
    ),

    DioExceptionType.badResponse => _mapStatusCode(exception),

    DioExceptionType.unknown => _mapUnknown(exception),
  };

  AppFailure _mapStatusCode(DioException exception) {
    final Response<dynamic>? response = exception.response;
    final int? status = response?.statusCode;
    final String? serverMessage = extractServerMessage(response?.data);
    final StackTrace stackTrace = exception.stackTrace;

    if (status == null) {
      return ServerFailure(
        message: serverMessage ?? AppStrings.errorServer,
        cause: exception,
        stackTrace: stackTrace,
      );
    }
    if (status == 401) {
      return AuthFailure(
        message: serverMessage ?? AppStrings.errorUnauthorized,
        cause: exception,
        stackTrace: stackTrace,
      );
    }
    if (status == 403) {
      return AuthFailure(
        message: serverMessage ?? AppStrings.errorForbidden,
        isForbidden: true,
        cause: exception,
        stackTrace: stackTrace,
      );
    }
    if (status >= 500) {
      return ServerFailure(
        message: serverMessage ?? AppStrings.errorServer,
        statusCode: status,
        cause: exception,
        stackTrace: stackTrace,
      );
    }
    return ClientFailure(
      message: serverMessage ?? AppStrings.errorClient,
      statusCode: status,
      cause: exception,
      stackTrace: stackTrace,
    );
  }

  AppFailure _mapUnknown(DioException exception) {
    final Object? cause = exception.error;
    // 拦截器可能已经构造好了业务失败（如缓存未命中），此时原样透传，
    // 避免在映射环节把精确的错误语义磨成笼统的"未知错误"。
    if (cause is AppFailure) {
      return cause;
    }
    // 走到 unknown 分支时，往往是响应体与模型对不上（JSON 解析失败、
    // 字段类型不符），这类问题重试也不会成功，需要归到解析失败。
    if (cause is FormatException || cause is TypeError) {
      return ParseFailure(
        message: AppStrings.errorParse,
        cause: cause,
        stackTrace: exception.stackTrace,
      );
    }
    return UnknownFailure(
      message: AppStrings.errorUnknown,
      cause: cause ?? exception,
      stackTrace: exception.stackTrace,
    );
  }
}

/// 默认的服务端文案提取：读取 JSON 对象里的 `message` 字段。
///
/// 后端约定不同时，替换这个函数即可，无需改动映射逻辑。
String? defaultServerMessage(Object? responseData) {
  if (responseData is! String) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(responseData);
    if (decoded is Map<String, dynamic>) {
      final Object? message = decoded['message'];
      return message is String && message.trim().isNotEmpty ? message : null;
    }
  } on FormatException {
    // 不是 JSON，交给默认文案兜底。
    return null;
  }
  return null;
}
