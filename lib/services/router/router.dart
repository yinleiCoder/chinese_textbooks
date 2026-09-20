/// 路由的**与页面无关**的部分。
///
/// 只放两样东西：
/// - `AppRoutes`：路径与名称常量，不含任何页面依赖；
/// - `AppNavigatorObserver`：导航日志。
///
/// 路由表本身（`AppNavigator`）在 `pages/app_navigator.dart`——它必须 import
/// 每一个页面，放在服务层会形成 `services → pages` 的反向依赖。
library;

export 'app_navigator_observer.dart';
export 'app_routes.dart';
