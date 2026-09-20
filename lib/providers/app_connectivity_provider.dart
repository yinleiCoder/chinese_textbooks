import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/connectivity/connectivity_service.dart';

/// 在线状态。
///
/// 它是 [ConnectivityService] 在 widget 树中的投影：把服务层的
/// `Stream<bool>` 转成 [ChangeNotifier]，让页面可以用
/// `context.watch<AppConnectivityProvider>()` 直接消费。
///
/// 这一层不是多余的——服务层不应该依赖 Flutter，而 UI 层不应该处理
/// 订阅生命周期，两侧各退一步，中间就需要这么薄薄一层。
final class AppConnectivityProvider extends ChangeNotifier {
  AppConnectivityProvider({required ConnectivityService service})
    : _service = service,
      _isOnline = service.isOnline {
    _subscription = _service.onStatusChanged.listen(_onStatusChanged);
  }

  final ConnectivityService _service;
  late final StreamSubscription<bool> _subscription;

  bool _isOnline;

  /// 当前是否在线。
  bool get isOnline => _isOnline;

  /// 当前是否离线。
  bool get isOffline => !_isOnline;

  void _onStatusChanged(bool isOnline) {
    if (_isOnline == isOnline) {
      return;
    }
    _isOnline = isOnline;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
