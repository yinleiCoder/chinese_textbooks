import 'package:flutter/foundation.dart';

import '../entity/entity.dart';
import '../services/http/http.dart';
import '../services/logger/app_logger.dart';
import '../services/storage/storage.dart';
import '../values/values.dart';

/// 登录态。
///
/// 同时是 [NdCredentialProvider] 的实现——网络层需要它来算 `X-ND-AUTH`，
/// 但它不该知道凭据存在哪、怎么刷新，那些职责留在这一层。
///
/// **凭据只进安全存储。** `mac_key` 是签名密钥，落明文等同于把账号交出去；
/// 桌面端安全存储不可用时会降级为"仅本次会话有效"，而不是写进
/// `shared_preferences`。这一点在设置页会明确告诉用户。
final class AuthSessionProvider extends ChangeNotifier
    implements NdCredentialProvider {
  AuthSessionProvider({required this._secureStorage, required this._logger});

  final KeyValueStore _secureStorage;
  final AppLogger _logger;

  NdCredential? _credential;

  /// 是否已登录。
  bool get isLoggedIn => _credential != null;

  /// 是否具备生成真实签名的能力。
  ///
  /// 只有 `access_token` 而没有 `mac_key` 的老格式凭据不够用——
  /// 它能读公开接口，但下不了需要签名的教材。
  bool get canSign => _credential?.canSign ?? false;

  /// 凭据是否只在内存里（安全存储不可用，退出应用即失效）。
  bool get isSessionOnly => _sessionOnly;
  bool _sessionOnly = false;

  /// 启动时从安全存储读回凭据。
  Future<void> load() async {
    try {
      final String? raw = await _secureStorage.readString(
        StorageKeys.ndCredential,
      );
      if (raw == null || raw.isEmpty) {
        return;
      }
      _credential = NdCredential.tryParse(raw);
      if (_credential != null) {
        _logger.i('已恢复登录态（可签名：$canSign）');
        notifyListeners();
      }
    } on Object catch (error, stackTrace) {
      // 读不出来等同于未登录，不该拦住启动。
      _logger.w('读取登录凭据失败', error, stackTrace);
    }
  }

  /// 保存凭据。
  Future<void> save(NdCredential value) async {
    _credential = value;
    _sessionOnly = false;
    notifyListeners();
    await _persist();
  }

  /// 退出登录。
  Future<void> clear() async {
    if (_credential == null) {
      return;
    }
    _credential = null;
    _sessionOnly = false;
    notifyListeners();
    try {
      await _secureStorage.delete(StorageKeys.ndCredential);
    } on Object catch (error, stackTrace) {
      _logger.w('清除登录凭据失败', error, stackTrace);
    }
  }

  // ==================== NdCredentialProvider ====================

  @override
  Future<NdCredential?> credential() async => _credential;

  @override
  Future<void> onCredentialRejected() async {
    _logger.w('平台拒绝了签名，已清除本地凭据');
    await clear();
  }

  // ==================== 内部实现 ====================

  Future<void> _persist() async {
    final NdCredential? value = _credential;
    if (value == null) {
      return;
    }
    try {
      await _secureStorage.writeString(
        StorageKeys.ndCredential,
        value.encode(),
      );
    } on Object catch (error, stackTrace) {
      // 安全存储不可用（桌面端较常见）：降级为仅本次会话有效。
      // **绝不退回到明文存储**——那等于把签名密钥交出去。
      _sessionOnly = true;
      _logger.w('安全存储不可用，本次登录仅在当前会话内有效', error, stackTrace);
      notifyListeners();
    }
  }
}
