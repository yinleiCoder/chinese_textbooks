/// 状态层。
///
/// 约定：
/// - 一律使用 `ChangeNotifier` + `context.watch` / `context.read`，
///   不引入额外的框架抽象；
/// - 状态类是**普通 Dart 对象**，依赖全部通过构造函数注入，
///   因此可以脱离 widget 树单独写单元测试；
/// - 页面级状态请放在 `pages/<功能>/` 目录下与该页面同名的文件里，
///   只有需要跨页面共享的状态才放在这里。
library;

export 'app_connectivity_provider.dart';
export 'app_locale_provider.dart';
export 'app_theme_provider.dart';
export 'auth_session_provider.dart';
export 'catalog_provider.dart';
export 'download_provider.dart';
export 'library_provider.dart';
