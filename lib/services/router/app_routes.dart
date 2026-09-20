/// 路由表常量。
///
/// 路径与名称成对声明，避免在页面里散落字符串字面量：
/// - 跳转用**名称**（`context.goNamed(AppRoutes.browseName)`），
///   这样将来调整路径不会漏改调用点；
/// - 需要拼接路径参数时才用**路径**。
abstract final class AppRoutes {
  // ==================== 外壳与四个 Tab ====================

  /// 书架（首页）。
  static const String libraryPath = '/';
  static const String libraryName = 'library';

  /// 目录。
  static const String browsePath = '/browse';
  static const String browseName = 'browse';

  /// 下载。
  static const String downloadsPath = '/downloads';
  static const String downloadsName = 'downloads';

  /// 设置。
  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  // ==================== 全屏页（在 Tab 外壳之外） ====================

  /// 目录下载 / 更新。
  static const String catalogSetupPath = '/catalog-setup';
  static const String catalogSetupName = 'catalogSetup';

  /// 教材详情。
  static const String textbookDetailPath = '/textbook/:id';
  static const String textbookDetailName = 'textbookDetail';

  /// 阅读器。
  static const String readerPath = '/textbook/:id/reader';
  static const String readerName = 'reader';

  /// 登录。
  static const String loginPath = '/login';
  static const String loginName = 'login';

  // ==================== 404 ====================

  /// 页面不存在。
  static const String notFoundPath = '/not-found';
  static const String notFoundName = 'notFound';

  // ==================== 路径拼接 ====================

  /// 教材详情的具体路径。
  static String textbookDetail(String contentId) => '/textbook/$contentId';

  /// 阅读器的具体路径。
  static String reader(String contentId) => '/textbook/$contentId/reader';
}
