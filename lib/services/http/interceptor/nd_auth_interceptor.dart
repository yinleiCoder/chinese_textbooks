import 'dart:io';

import 'package:dio/dio.dart';

import '../../../entity/entity.dart';
import '../../../values/values.dart';
import '../../logger/app_logger.dart';
import '../nd_auth_signer.dart';
import '../nd_credential_provider.dart';

/// 平台请求头与签名注入。
///
/// **必须是普通 [Interceptor]，不能是 `QueuedInterceptor`。**
/// 签名要求"每个 URL 现算"，而排队执行会把三路并发的下载串行化。
///
/// 三件事：
/// 1. 补上 CDN 会校验的来源头（`Origin` / `Referer` / `User-Agent`）；
/// 2. 注入 `Authorization`（未登录时是站点前端的匿名形式 `Bearer 0`）；
/// 3. 现算 `X-ND-AUTH`。
final class NdAuthInterceptor extends Interceptor {
  NdAuthInterceptor({
    required this._credentialProvider,
    required this._signer,
    required this._logger,
  });

  final NdCredentialProvider _credentialProvider;
  final NdAuthSigner _signer;
  final AppLogger _logger;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    _applyPlatformHeaders(options);

    final NdCredential? credential = await _credentialProvider.credential();
    options.headers[HttpHeaders.authorizationHeader] = credential == null
        ? NdConfig.anonymousAuthorization
        : 'Bearer ${credential.accessToken}';

    // 对公开的 JSON 接口带签名是无害的（它们不校验），
    // 因此不按主机分情况，统一现算，少一个分支就少一处出错的地方。
    options.headers[NdConfig.ndAuthHeader] = _signer.headerValue(
      credential: credential,
      method: options.method,
      url: options.uri,
    );

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int? status = err.response?.statusCode;
    final bool rejected =
        status == HttpStatus.unauthorized || status == HttpStatus.forbidden;

    // **只有私有 CDN 上的 401/403 才代表凭据失效。**
    //
    // 这个区分至关重要：详情接口（`s-file-*`）对少数条目返回 403 是
    // "这本教材只有子资源、没有独立详情"，与登录状态毫无关系。
    // 不做这个区分的话，用户翻到某本残缺教材就会被莫名其妙地登出。
    if (rejected && _isPrivateCdnHost(err.requestOptions.uri.host)) {
      final NdCredential? credential = await _credentialProvider.credential();
      if (credential != null) {
        _logger.w('平台拒绝了签名，触发登出流程：${err.requestOptions.uri.path}');
        await _credentialProvider.onCredentialRejected();
      }
    }
    handler.next(err);
  }

  /// 补全平台要求的来源头。
  ///
  /// 用 `putIfAbsent` 而不是直接赋值：调用方显式指定的值优先。
  void _applyPlatformHeaders(RequestOptions options) {
    options.headers
      ..putIfAbsent(HttpHeaders.userAgentHeader, () => NdConfig.userAgent)
      ..putIfAbsent('Origin', () => NdConfig.origin)
      ..putIfAbsent(HttpHeaders.refererHeader, () => NdConfig.referer);
  }

  /// 是否指向需要签名的私有 CDN。
  static bool _isPrivateCdnHost(String host) =>
      NdConfig.privateHosts.contains(host);
}
