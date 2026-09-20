import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../values/values.dart';

/// 网络层配置值对象。
///
/// 把散落在 [BaseOptions] 里的参数收敛成一个不可变对象，
/// 好处是配置可以被测试替换、可以按环境派生、也能直接被断言比较。
final class HttpConfig extends Equatable {
  const HttpConfig({
    required this.baseUrl,
    this.connectTimeout = AppConfig.connectTimeout,
    this.sendTimeout = AppConfig.sendTimeout,
    this.receiveTimeout = AppConfig.receiveTimeout,
    this.maxRetries = AppConfig.maxRetries,
    this.retryBackoff = AppConfig.retryBackoff,
    this.enableLogging = false,
  });

  /// 按运行环境派生配置。
  ///
  /// [baseUrl] 由 `AppConfig.apiBaseUrl` 与 `AppConfig.apiPrefix` 拼成；
  /// 平台不使用版本前缀，因此拼接结果就是平台 JSON 主机本身。
  factory HttpConfig.forEnvironment(
    AppEnvironment environment, {
    bool enableLogging = false,
  }) => HttpConfig(
    baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
    enableLogging: enableLogging || environment.verboseLogging,
  );

  /// 接口根地址（含版本前缀）。
  final String baseUrl;

  /// 建立连接的超时时间。
  final Duration connectTimeout;

  /// 发送数据的超时时间。
  final Duration sendTimeout;

  /// 接收数据的超时时间。
  final Duration receiveTimeout;

  /// 幂等请求的最大重试次数（不含首次）。
  final int maxRetries;

  /// 重试的退避基数。
  final Duration retryBackoff;

  /// 是否输出请求日志。
  final bool enableLogging;

  /// 转换为 dio 的基础配置。
  BaseOptions toBaseOptions() => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: connectTimeout,
    sendTimeout: sendTimeout,
    receiveTimeout: receiveTimeout,
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
    headers: const <String, dynamic>{
      Headers.acceptHeader: Headers.jsonContentType,
    },
  );

  @override
  List<Object?> get props => <Object?>[
    baseUrl,
    connectTimeout,
    sendTimeout,
    receiveTimeout,
    maxRetries,
    retryBackoff,
    enableLogging,
  ];
}
