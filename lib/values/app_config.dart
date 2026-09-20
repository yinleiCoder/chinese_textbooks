import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'nd_config.dart';

/// 应用运行环境。
///
/// 环境差异（接口域名、日志级别、缓存容量）全部收敛在这里，
/// 业务代码永远不应该出现按环境分支的 `if`。
///
/// 切换方式：
/// ```bash
/// flutter run --dart-define=APP_ENV=staging
/// ```
enum AppEnvironment {
  /// 开发环境：本地联调，开启全量日志。
  dev(label: '开发环境', verboseLogging: true),

  /// 预发环境：与生产同构，保留日志用于验收排查。
  staging(label: '预发环境', verboseLogging: true),

  /// 生产环境：关闭调试日志，仅保留警告及以上。
  prod(label: '生产环境', verboseLogging: false);

  const AppEnvironment({required this.label, required this.verboseLogging});

  /// 环境中文名，用于"关于"页等展示场景。
  final String label;

  /// 是否输出调试级别日志。
  final bool verboseLogging;

  /// 是否为生产环境。
  bool get isProduction => this == AppEnvironment.prod;
}

/// 全局静态配置。
///
/// 这里只存放**编译期可确定**的常量。任何需要在运行时变更的配置
/// （主题、语言、登录态）都应该由 `providers/` 中的状态类托管。
abstract final class AppConfig {
  /// 应用展示名称。
  ///
  /// 两端原生工程里各有一份同名的拷贝（Android 的 `android:label`、
  /// Windows 的窗口标题与 `ProductName`），改名字时四处要一起改。
  static const String appName = '无界课本';

  /// 应用版本号。
  ///
  /// 与 `pubspec.yaml` 的 `version` 手工保持一致。没有引入 `package_info_plus`
  /// 是因为它为一个展示用途的字符串多加一个原生插件并不划算。
  static const String appVersion = '1.0.0';

  /// 通过 `--dart-define=APP_ENV=xxx` 注入的环境标识。
  static const String _environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// 当前运行环境，默认为 [AppEnvironment.dev]。
  static AppEnvironment get environment => switch (_environmentName) {
    'prod' => AppEnvironment.prod,
    'staging' => AppEnvironment.staging,
    _ => AppEnvironment.dev,
  };

  // ==================== 屏幕适配 ====================

  /// 设计稿尺寸（单位 dp），必须与 UI 设计稿保持一致。
  ///
  /// 该值同时传给 `ScreenUtilInit`，是 `.w` / `.h` / `.r` / `.sp` 的换算基准。
  static const Size designSize = Size(360, 690);

  /// 当前是否为桌面平台。
  static bool get isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  /// 是否启用等比缩放。
  ///
  /// **桌面端不缩放。** `flutter_screenutil` 解决的是"手机屏幕尺寸差异大、
  /// 按设计稿等比缩放"的问题，设计稿是 360×690 的手机尺寸。到了桌面上，
  /// 窗口常有 1500 逻辑像素宽，按宽度算缩放比接近 4.3 倍——20sp 的标题会被
  /// 放大到八十多像素，整个界面变成一台"放大的手机"。
  ///
  /// 桌面用户期望的恰恰相反：窗口越大，**看到的内容越多**，而不是字越大。
  /// 因此这里让 `AppDimens` 在桌面端直接返回设计值（1 设计单位 = 1 逻辑像素），
  /// 移动端仍按设计稿等比适配。
  static bool get scaleUi => !isDesktop;

  /// 设计稿宽度，供少数需要自行计算比例的场景使用。
  static double get designWidth => designSize.width;

  /// 设计稿高度。
  static double get designHeight => designSize.height;

  // ==================== 网络 ====================

  /// 接口根地址。
  ///
  /// 本应用没有自己的后端，唯一的服务对象是智慧教育平台，
  /// 因此这里直接指向平台的 JSON 主机（详见 [NdConfig.jsonHost]）。
  /// 平台是外部公共服务，不存在 dev / staging 之分，[AppEnvironment] 只用来控制日志级别。
  static const String apiBaseUrl = NdConfig.jsonHost;

  /// 接口统一前缀。
  ///
  /// 平台不使用版本前缀——版本信息在路径里（`/zxx/ndrs/...`、`/zxx/ndrv2/...`），
  /// 因此这里留空。保留该常量是为了让 `HttpConfig` 的拼接逻辑仍然成立。
  static const String apiPrefix = '';

  /// 建立连接的超时时间。
  static const Duration connectTimeout = Duration(seconds: 15);

  /// 发送数据的超时时间。
  static const Duration sendTimeout = Duration(seconds: 20);

  /// 接收数据的超时时间。
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// 幂等请求的最大重试次数（不含首次请求）。
  static const int maxRetries = 2;

  /// 重试的基础退避时长，实际间隔按指数增长。
  static const Duration retryBackoff = Duration(milliseconds: 400);

  // ==================== 缓存 ====================

  /// 内存缓存（一级缓存）的条目上限，超出后按 LRU 淘汰。
  static const int memoryCacheCapacity = 120;

  /// 持久化缓存（二级缓存）的键前缀，用于隔离业务数据。
  static const String cacheNamespace = 'cache';

  /// 磁盘缓存条目上限，防止无限增长。
  static const int persistentCacheCapacity = 400;

  /// 缓存清理的默认时长，超过该时长且未被访问的条目会被回收。
  static const Duration cacheRetention = Duration(days: 7);
}
