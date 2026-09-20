/// 全局服务层。
///
/// 这里放"与具体业务无关、但需要跨页面共享"的能力：
/// 日志、存储、缓存、网络传输、路由、连通性。
///
/// 依赖方向（箭头表示"依赖"）：
/// ```
/// apis/ ──▶ services/ ──▶ utils/ ──▶ values/
/// providers/ ──▶ apis/ + services/
/// pages/ + widgets/ ──▶ providers/ + values/
/// ```
/// `app_dependencies.dart` 是唯一的例外——它是组合根，
/// 需要认识所有层才能把它们装配起来。
library;

export 'app_dependencies.dart';
export 'auth/auth.dart';
export 'cache/cache.dart';
export 'catalog/catalog.dart';
export 'connectivity/connectivity.dart';
export 'download/download.dart';
export 'export/export.dart';
export 'http/http.dart';
export 'logger/app_logger.dart';
export 'router/router.dart';
export 'storage/storage.dart';
