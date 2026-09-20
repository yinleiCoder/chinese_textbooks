/// 统一失败模型。
///
/// 设计要点：
/// - 使用 `sealed` 关键字，配合 Dart 3 的 `switch` 模式匹配可以做到**穷尽检查**，
///   新增一种失败类型时编译器会强制所有分支处理它；
/// - 与网络实现完全解耦：`dio` 的 `DioException` 由 `apis/` 层的映射器转换到这里，
///   因此 `utils/` 不依赖任何网络库，UI 层也只需要认识这一套类型；
/// - 携带 `cause` / `stackTrace` 便于日志上报，但不对外暴露给用户。
sealed class AppFailure implements Exception {
  const AppFailure({required this.message, this.cause, this.stackTrace});

  /// 可直接展示给用户的中文提示。
  final String message;

  /// 原始异常，仅用于日志与排查。
  final Object? cause;

  /// 原始堆栈。
  final StackTrace? stackTrace;

  /// 失败类型的可读名称。
  ///
  /// 刻意不用 `runtimeType.toString()`：AOT 编译配合代码混淆之后，
  /// 类型名可能被裁剪成无意义的符号，日志就失去了排查价值。
  /// 改用穷尽 `switch` 还有个额外好处——新增子类时编译器会强制在这里补一行。
  String get typeName => switch (this) {
    NetworkFailure() => 'NetworkFailure',
    ServerFailure() => 'ServerFailure',
    ClientFailure() => 'ClientFailure',
    BusinessFailure() => 'BusinessFailure',
    AuthFailure() => 'AuthFailure',
    ParseFailure() => 'ParseFailure',
    CacheFailure() => 'CacheFailure',
    CancelledFailure() => 'CancelledFailure',
    UnknownFailure() => 'UnknownFailure',
  };

  @override
  String toString() => '$typeName(message: $message, cause: $cause)';
}

/// 网络层失败：无连接、DNS 解析失败、连接被拒等。
final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    required super.message,
    this.isTimeout = false,
    super.cause,
    super.stackTrace,
  });

  /// 是否为超时（超时通常可以给出"稍后重试"以外的更明确提示）。
  final bool isTimeout;
}

/// 服务端失败：5xx，或响应体不符合约定的结构。
final class ServerFailure extends AppFailure {
  const ServerFailure({
    required super.message,
    this.statusCode,
    this.traceId,
    super.cause,
    super.stackTrace,
  });

  /// HTTP 状态码。
  final int? statusCode;

  /// 服务端返回的链路追踪 ID，便于对账排查。
  final String? traceId;
}

/// 客户端失败：4xx，请求本身有问题。
final class ClientFailure extends AppFailure {
  const ClientFailure({
    required super.message,
    required this.statusCode,
    this.code,
    super.cause,
    super.stackTrace,
  });

  /// HTTP 状态码。
  final int statusCode;

  /// 业务错误码。
  final String? code;
}

/// 业务失败：HTTP 层成功（2xx），但业务返回码表示这次操作没有成功。
///
/// 这类失败单看 HTTP 状态码是发现不了的，必须解开响应体才能判断，
/// 因此单独成一个类型，避免和传输层错误混在一起。
final class BusinessFailure extends AppFailure {
  const BusinessFailure({
    required this.code,
    required super.message,
    this.data,
    super.cause,
    super.stackTrace,
  });

  /// 业务错误码。
  final String code;

  /// 服务端随错误一起返回的附加数据（如剩余次数、重试时间）。
  final Object? data;
}

/// 认证失败：401 未登录 / 403 无权限。
final class AuthFailure extends AppFailure {
  const AuthFailure({
    required super.message,
    this.isForbidden = false,
    super.cause,
    super.stackTrace,
  });

  /// `true` 表示 403（已登录但无权限），`false` 表示 401（未登录或登录态失效）。
  final bool isForbidden;
}

/// 解析失败：响应体不是合法 JSON，或字段类型与模型不符。
final class ParseFailure extends AppFailure {
  const ParseFailure({required super.message, super.cause, super.stackTrace});
}

/// 缓存失败：本地存储读写异常。
///
/// 缓存失败**不应该中断业务流程**，调用方应当降级为直接请求网络。
final class CacheFailure extends AppFailure {
  const CacheFailure({required super.message, super.cause, super.stackTrace});
}

/// 请求被主动取消。
///
/// 页面销毁导致的取消属于正常流程，UI 不应弹出错误提示。
final class CancelledFailure extends AppFailure {
  const CancelledFailure({
    required super.message,
    super.cause,
    super.stackTrace,
  });
}

/// 兜底失败：无法归类的异常。
final class UnknownFailure extends AppFailure {
  const UnknownFailure({required super.message, super.cause, super.stackTrace});
}

/// [AppFailure] 的便捷判断。
extension AppFailureX on AppFailure {
  /// 是否为需要用户重新登录的失败。
  bool get requiresReLogin => switch (this) {
    AuthFailure(isForbidden: false) => true,
    _ => false,
  };

  /// 是否适合提示用户"重试"。
  ///
  /// 取消属于用户主动行为，解析失败重试也不会成功，两者都不该给重试入口。
  bool get isRetryable => switch (this) {
    NetworkFailure() => true,
    ServerFailure() => true,
    CancelledFailure() => false,
    ParseFailure() => false,
    ClientFailure() => false,
    BusinessFailure() => false,
    AuthFailure() => false,
    CacheFailure() => false,
    UnknownFailure() => true,
  };
}
