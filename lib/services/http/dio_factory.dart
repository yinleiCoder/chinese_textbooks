import 'package:dio/dio.dart';

import '../cache/cache.dart';
import '../logger/app_logger.dart';
import 'http_config.dart';
import 'interceptor/cache_interceptor.dart';
import 'interceptor/log_interceptor.dart';
import 'interceptor/nd_auth_interceptor.dart';
import 'interceptor/retry_interceptor.dart';
import 'nd_auth_signer.dart';
import 'nd_credential_provider.dart';

/// `Dio` 实例工厂（工厂模式 + 组合根的一部分）。
///
/// 把"创建客户端"和"配置客户端"这两件事从业务代码里剥离出去：
/// 业务侧只会拿到一个**已经装配好全部拦截器**的 `Dio`，
/// 不需要知道缓存、重试、签名是怎么接上去的。
///
/// 本应用只对接智慧教育平台，因此全部客户端都装 [NdAuthInterceptor]。
final class DioFactory {
  const DioFactory({
    required this._logger,
    required this._cache,
    required this._policyRegistry,
    required this._credentialProvider,
    required this._signer,
  });

  final AppLogger _logger;
  final CacheManager _cache;
  final CachePolicyRegistry _policyRegistry;
  final NdCredentialProvider _credentialProvider;
  final NdAuthSigner _signer;

  /// 创建平台客户端：用于目录、详情等 **JSON 请求**。
  ///
  /// **拦截器顺序是有讲究的**，dio 按加入顺序形成队列，请求与响应都顺着队列走：
  ///
  /// | 顺序 | 拦截器 | 为什么在这个位置 |
  /// | --- | --- | --- |
  /// | 1 | `NdAuthInterceptor` | 最先执行，保证后续日志与缓存看到的是带签名的最终请求 |
  /// | 2 | `AppLogInterceptor` | 在缓存之前，才能记录到"缓存命中"这类响应 |
  /// | 3 | `CacheInterceptor` | 包住真实网络调用，缓存命中时内层拦截器不会执行 |
  /// | 4 | `RetryInterceptor` | 最内层，重试只重发网络请求，不会重复写缓存或重复算签名 |
  Dio createPlatformClient(HttpConfig config) {
    final Dio dio = Dio(config.toBaseOptions());
    dio.interceptors.addAll(<Interceptor>[
      NdAuthInterceptor(
        credentialProvider: _credentialProvider,
        signer: _signer,
        logger: _logger,
      ),
      if (config.enableLogging) AppLogInterceptor(logger: _logger),
      CacheInterceptor(
        cache: _cache,
        logger: _logger,
        policyRegistry: _policyRegistry,
        // 复用同一个实例：后台刷新也要走签名与日志。
        revalidationClient: dio,
      ),
      RetryInterceptor(
        logger: _logger,
        client: dio,
        maxRetries: config.maxRetries,
        backoff: config.retryBackoff,
      ),
    ]);
    return dio;
  }

  /// 创建下载客户端：用于教材正文的**二进制流**。
  ///
  /// 与平台客户端的差异，每一条都有明确理由：
  ///
  /// - **不装 `CacheInterceptor`**：响应是几十 MB 的二进制流，
  ///   进 KV 缓存既无意义又会把 `shared_preferences` 撑爆；
  /// - **不装 `RetryInterceptor`**：重试策略由 `DownloadWorker` 统一负责
  ///   （镜像轮换 + 400 退避 + 限流闸门），两套重试叠加会打乱配额节奏——
  ///   而这正是平台最敏感的环节。
  Dio createDownloadClient(HttpConfig config) {
    final Dio dio = Dio(config.toBaseOptions());
    dio.interceptors.addAll(<Interceptor>[
      NdAuthInterceptor(
        credentialProvider: _credentialProvider,
        signer: _signer,
        logger: _logger,
      ),
      if (config.enableLogging) AppLogInterceptor(logger: _logger),
    ]);
    return dio;
  }
}
