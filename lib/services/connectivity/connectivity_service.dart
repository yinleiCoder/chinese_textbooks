import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../logger/app_logger.dart';

/// 网络连通性服务。
///
/// 把 `connectivity_plus` 的"结果列表"细节收敛成一个布尔值：
/// 上层只关心"现在能不能联网"，不关心当前是 Wi-Fi 还是蜂窝。
///
/// 它**不拦截请求**。缓存层已经能优雅地处理断网（网络优先策略会自动
/// 回落到缓存），再插一个"离线就拒绝请求"的拦截器反而会破坏这条降级路径。
/// 这个服务的用途是给 UI 提供状态：显示离线角标、禁用需要联网的按钮。
final class ConnectivityService {
  ConnectivityService({required this._logger, Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final AppLogger _logger;
  final Connectivity _connectivity;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// 初始视为在线，避免启动瞬间误报离线；[start] 会立刻校正。
  bool _isOnline = true;

  /// 当前是否在线。
  bool get isOnline => _isOnline;

  /// 在线状态变化流。
  ///
  /// 只在状态**真正翻转**时发射，重复的相同状态不会打扰订阅者。
  Stream<bool> get onStatusChanged => _controller.stream;

  /// 开始监听。
  ///
  /// 幂等：重复调用不会产生多个订阅。
  Future<void> start() async {
    if (_subscription != null) {
      return;
    }
    final List<ConnectivityResult> results = await _connectivity
        .checkConnectivity();
    _update(_isOnlineResult(results));

    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) => _update(_isOnlineResult(results)),
      onError: (Object error, StackTrace stackTrace) {
        _logger.w('连通性监听异常', error, stackTrace);
      },
    );
  }

  /// 停止监听并释放资源。
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }

  /// 连通性结果列表 → 是否在线。
  ///
  /// 结果是一个列表（设备可能同时连着 Wi-Fi 和蜂窝），
  /// 只要**存在任意一个非 none 的结果**就说明有网络出口。
  static bool _isOnlineResult(List<ConnectivityResult> results) => results.any(
    (ConnectivityResult result) => result != ConnectivityResult.none,
  );

  /// 更新状态，仅在翻转时通知订阅者。
  void _update(bool isOnline) {
    if (_isOnline == isOnline) {
      return;
    }
    _isOnline = isOnline;
    _logger.i('网络状态变化：${isOnline ? '在线' : '离线'}');
    if (!_controller.isClosed) {
      _controller.add(isOnline);
    }
  }
}
