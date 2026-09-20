import '../../entity/entity.dart';

/// 平台凭据提供方。
///
/// 网络层需要凭据来算签名，但不应该知道它存在哪、怎么刷新、什么时候过期——
/// 那些属于登录态的职责。这里只定义一个最小契约，
/// 由 `providers/` 中的 `AuthSessionProvider` 实现；
/// 登录功能尚未接入时用 [AnonymousCredentialProvider] 占位。
abstract interface class NdCredentialProvider {
  /// 取得当前凭据，未登录时返回 `null`。
  Future<NdCredential?> credential();

  /// 签名被服务端拒绝时的回调（401 / 403）。
  ///
  /// 实现方应当清理本地凭据并引导用户重新登录。
  Future<void> onCredentialRejected();
}

/// 匿名实现：不提供凭据，被拒时什么也不做。
///
/// 公开的目录与详情接口本来就不校验签名，因此应用在未登录状态下
/// 也能完整地浏览教材——只是下载不了需要凭据的那部分。
final class AnonymousCredentialProvider implements NdCredentialProvider {
  const AnonymousCredentialProvider();

  @override
  Future<NdCredential?> credential() async => null;

  @override
  Future<void> onCredentialRejected() async {}
}
