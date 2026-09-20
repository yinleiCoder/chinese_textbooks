import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../entity/entity.dart';
import '../services/router/app_routes.dart';
import 'browse/browse.dart';
import 'catalog/catalog_setup_page.dart';
import 'downloads/downloads.dart';
import 'error/not_found_page.dart';
import 'library/library.dart';
import 'login/login_page.dart';
import 'reader/reader_page.dart';
import 'settings/settings.dart';
import 'shell/home_shell.dart';
import 'textbook/textbook_detail_page.dart';

/// 路由表组装。
///
/// **放在 `pages/` 而不是 `services/router/`**：路由表本质上是"页面怎么拼装"，
/// 它必须 import 每一个页面。放在服务层会形成 `services → pages` 的反向依赖，
/// 与既定的分层方向矛盾。`services/router/` 只保留与页面无关的部分
/// （路径常量、导航观察者）。
abstract final class AppNavigator {
  /// 创建路由实例。
  ///
  /// 之所以是"静态工厂 + 可注入参数"而不是全局单例：
  /// - `refreshListenable` 需要绑定登录态，而登录态是运行期才存在的对象；
  /// - 统一鉴权的 `redirect` 应当可替换、可测试；
  /// - 测试里可以传入不同的 `initialLocation` 直接跳到目标页面。
  static GoRouter create({
    String initialLocation = AppRoutes.libraryPath,
    GlobalKey<NavigatorState>? navigatorKey,
    Listenable? refreshListenable,
    GoRouterRedirect? redirect,
    List<NavigatorObserver>? observers,
    bool debugLogDiagnostics = false,
  }) {
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      refreshListenable: refreshListenable,
      redirect: redirect,
      observers: observers,
      debugLogDiagnostics: debugLogDiagnostics,
      // 未匹配到任何路由时统一落到 404 页，而不是 Flutter 默认的红色错误屏。
      errorBuilder: (BuildContext context, GoRouterState state) =>
          NotFoundPage(location: state.uri.toString()),
      routes: <RouteBase>[
        // ---------- 四个 Tab ----------
        // 用 StatefulShellRoute.indexedStack 而不是普通 ShellRoute：
        // 前者为每个分支维护独立的导航栈与滚动位置，切回来时仍在原处，
        // 这是 Tab 导航的基本预期。
        StatefulShellRoute.indexedStack(
          builder: (
            BuildContext context,
            GoRouterState state,
            StatefulNavigationShell navigationShell,
          ) => HomeShell(navigationShell: navigationShell),
          branches: <StatefulShellBranch>[
            _branch(
              AppRoutes.libraryPath,
              AppRoutes.libraryName,
              const LibraryPage(),
            ),
            _branch(
              AppRoutes.browsePath,
              AppRoutes.browseName,
              const BrowsePage(),
            ),
            _branch(
              AppRoutes.downloadsPath,
              AppRoutes.downloadsName,
              const DownloadsPage(),
            ),
            _branch(
              AppRoutes.settingsPath,
              AppRoutes.settingsName,
              const SettingsPage(),
            ),
          ],
        ),

        // ---------- 全屏页 ----------
        // 放在外壳之外：全屏沉浸，不被底部导航遮挡。
        GoRoute(
          path: AppRoutes.catalogSetupPath,
          name: AppRoutes.catalogSetupName,
          builder: (BuildContext context, GoRouterState state) =>
              const CatalogSetupPage(showAppBar: true),
        ),
        GoRoute(
          path: AppRoutes.textbookDetailPath,
          name: AppRoutes.textbookDetailName,
          builder: (BuildContext context, GoRouterState state) =>
              TextbookDetailPage(
                contentId: state.pathParameters['id']!,
                // 深链进入时 extra 为空，页面会少显示分类与出版社，不至于崩。
                summary: state.extra as Textbook?,
              ),
        ),
        GoRoute(
          path: AppRoutes.readerPath,
          name: AppRoutes.readerName,
          builder: (BuildContext context, GoRouterState state) => ReaderPage(
            textbookId: state.pathParameters['id']!,
            title: state.extra as String?,
          ),
        ),
        GoRoute(
          path: AppRoutes.loginPath,
          name: AppRoutes.loginName,
          builder: (BuildContext context, GoRouterState state) =>
              const LoginPage(),
        ),
        GoRoute(
          path: AppRoutes.notFoundPath,
          name: AppRoutes.notFoundName,
          builder: (BuildContext context, GoRouterState state) =>
              NotFoundPage(location: state.uri.toString()),
        ),

        // 教材详情、阅读器、登录在对应功能落地时追加在这里。
      ],
    );
  }

  /// 一条只有一个根页面的分支。
  static StatefulShellBranch _branch(String path, String name, Widget page) {
    return StatefulShellBranch(
      routes: <RouteBase>[
        GoRoute(
          path: path,
          name: name,
          builder: (BuildContext context, GoRouterState state) => page,
        ),
      ],
    );
  }
}
