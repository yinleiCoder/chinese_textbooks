import 'package:flutter/widgets.dart';

import '../logger/app_logger.dart';

/// 记录页面跳转的导航观察者。
///
/// 排查"用户到底怎么走到这个页面的"这类问题时，
/// 一份带时间戳的页面栈变化日志比断点有效得多。
/// 生产环境会自动降级为不输出（日志级别由 `AppLogger` 控制）。
final class AppNavigatorObserver extends NavigatorObserver {
  AppNavigatorObserver({required this._logger});

  final AppLogger _logger;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logger.d('页面入栈：${_describe(previousRoute)} → ${_describe(route)}');
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logger.d('页面出栈：${_describe(route)} → ${_describe(previousRoute)}');
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _logger.d('页面替换：${_describe(oldRoute)} → ${_describe(newRoute)}');
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logger.d('页面移除：${_describe(route)}');
    super.didRemove(route, previousRoute);
  }

  /// 取路由名用于日志；未命名路由退回显示 route 类型。
  String _describe(Route<dynamic>? route) {
    if (route == null) {
      return '(空)';
    }
    final String? name = route.settings.name;
    return name != null && name.isNotEmpty ? name : route.toString();
  }
}
