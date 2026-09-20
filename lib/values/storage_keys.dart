/// 本地存储键名。
///
/// 集中声明的意义：同一个键会被"写入方"（`providers/` 中的状态类）
/// 和"读取方"（启动阶段的 `AppDependencies`）分别引用，
/// 若各自写字面量，改一处漏一处就会导致设置读不出来。
///
/// 命名约定：`模块:用途`，例如 `settings:themeMode`。
abstract final class StorageKeys {
  // ==================== 设置（明文存储即可） ====================

  /// 主题模式，取值为 `ThemeMode.name`。
  static const String themeMode = 'settings:themeMode';

  /// 语言，取值为语言标签（如 `zh`、`en`）；不存在表示跟随系统。
  static const String locale = 'settings:locale';

  /// 阅读进度键前缀，完整键为 `前缀 + 教材 id`。
  static const String readingProgress = 'reading:page:';

  /// 书架整理信息（置顶与分组）的 JSON。
  static const String libraryArrangement = 'library:arrangement';

  /// 是否已展示过引导页。
  static const String onboardingCompleted = 'settings:onboardingCompleted';

  // ==================== 凭据（存入安全存储） ====================

  /// 访问令牌。
  static const String accessToken = 'auth:accessToken';

  /// 刷新令牌。
  static const String refreshToken = 'auth:refreshToken';

  /// 平台登录凭据（`{access_token, mac_key, diff}` 的 JSON）。
  ///
  /// **必须存安全存储**，见 `AuthSessionProvider` 的注释。
  static const String ndCredential = 'auth:ndCredential';

  /// 当前登录用户 ID。
  ///
  /// 同时用作 HTTP 缓存的身份标识，避免切换账号后读到上一位用户的缓存。
  static const String userId = 'auth:userId';
}
