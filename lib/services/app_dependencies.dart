import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../apis/apis.dart';
import '../providers/auth_session_provider.dart';
import '../values/values.dart';
import 'cache/cache.dart';
import 'catalog/catalog.dart';
import 'connectivity/connectivity.dart';
import 'download/download.dart';
import 'http/http.dart';
import 'logger/app_logger.dart';
import 'storage/storage.dart';

/// 依赖容器 —— **组合根（Composition Root）**。
///
/// 整个应用中，只有这一个文件允许同时认识所有层：它知道缓存怎么建、
/// 网络怎么装配、接口客户端长什么样。其余所有代码都只通过构造函数
/// 接收自己需要的那几个依赖，因此：
/// - 每个类的依赖一目了然（看构造函数签名即可）；
/// - 单元测试可以逐个替换依赖，不需要任何全局状态；
/// - 依赖关系是显式的，不存在"某个模块偷偷 import 了一个单例"。
///
/// 生命周期：在 `main()` 中创建一次，通过 `Provider` 注入 widget 树。
final class AppDependencies {
  const AppDependencies({
    required this.logger,
    required this.preferences,
    required this.secureStorage,
    required this.paths,
    required this.cache,
    required this.cachePolicyRegistry,
    required this.dio,
    required this.apiClient,
    required this.textbookApi,
    required this.catalogRepository,
    required this.downloadManager,
    required this.connectivity,
    required this.authSession,
    required this.initialThemeMode,
    required this.initialLocale,
  });

  /// 日志。
  final AppLogger logger;

  /// 普通设置存储（明文）。
  final KeyValueStore preferences;

  /// 安全存储（加密），用于登录凭据。
  final KeyValueStore secureStorage;

  /// 应用私有目录布局。
  final AppPaths paths;

  /// 缓存门面。
  final CacheManager cache;

  /// 接口缓存策略注册表。
  final CachePolicyRegistry cachePolicyRegistry;

  /// 平台客户端（JSON 请求）。
  final Dio dio;

  /// 接口层客户端，把 [Dio] 的异常收敛为 `Result`。
  final ApiClient apiClient;

  /// 教材详情接口。
  final TextbookApi textbookApi;

  /// 教材目录仓储。
  final CatalogRepository catalogRepository;

  /// 下载队列。
  final DownloadManager downloadManager;

  /// 网络连通性。
  final ConnectivityService connectivity;

  /// 登录态。
  ///
  /// **只创建这一个实例**：网络层拿它算签名，界面拿它显示按钮文案，
  /// 下载器拿它决定走公开镜像还是私有域。早先两处各建一个，结果是
  /// 网络层永远看不到用户登录后的凭据——所有需要签名的下载都会 401。
  final AuthSessionProvider authSession;

  /// 启动时读到的主题模式。
  ///
  /// 在启动阶段一次性读出来，让首帧就渲染成用户上次选择的主题，
  /// 避免"先亮一下再变暗"的闪烁。
  final ThemeMode initialThemeMode;

  /// 启动时读到的语言；`null` 表示跟随系统。
  final Locale? initialLocale;

  /// 组装全部依赖。
  ///
  /// 调用前需要保证 `WidgetsFlutterBinding.ensureInitialized()` 已执行
  /// （见 `main.dart`），因为存储与路径都依赖平台通道。
  static Future<AppDependencies> create({AppEnvironment? environment}) async {
    final AppEnvironment env = environment ?? AppConfig.environment;

    await _initializeDateFormats();

    final AppLogger logger = AppLogger(verbose: env.verboseLogging);

    // ---------- 路径 ----------
    final AppPaths paths = await AppPaths.resolve();
    // 残留的 .tmp 无法判断完整性，而第一版不做断点续传，留着只会占空间
    // 并干扰"文件是否已存在"的判断。
    await paths.clearTmp();

    // ---------- 存储：两类数据物理隔离 ----------
    // 设置类数据量大但无需加密，走 shared_preferences；
    // 凭据类数据量小但必须加密，走系统安全存储。
    final KeyValueStore preferences = PreferencesStore(prefix: 'app:');
    final KeyValueStore secureStorage = SecureStore();

    // ---------- 缓存：内存 LRU（一级）+ 落盘（二级） ----------
    final MemoryCacheStore memoryStore = MemoryCacheStore();
    final PreferencesCacheStore persistentStore = PreferencesCacheStore(
      store: PreferencesStore(prefix: '${AppConfig.cacheNamespace}:'),
      logger: logger,
    );
    final CacheManager cache = CacheManager(
      store: TieredCacheStore(<CacheStore>[memoryStore, persistentStore]),
      // 与一级缓存是同一个实例：persist 为 false 的条目写进内存后，
      // 常规读取路径依然能在第一级命中它。
      transientStore: memoryStore,
      logger: logger,
    );

    // ---------- 网络 ----------
    final CachePolicyRegistry policyRegistry = CachePolicyRegistry();
    final AuthSessionProvider authSession = AuthSessionProvider(
      secureStorage: secureStorage,
      logger: logger,
    );
    await authSession.load();
    final Dio dio = DioFactory(
      logger: logger,
      cache: cache,
      policyRegistry: policyRegistry,
      credentialProvider: authSession,
      signer: NdAuthSigner(),
    ).createPlatformClient(HttpConfig.forEnvironment(env));

    final ApiClient apiClient = ApiClient(
      dio: dio,
      failureMapper: const DefaultFailureMapper(),
      logger: logger,
    );

    // ---------- 教材目录 ----------
    // 目录数据走独立的文件存储，**不进 KV 缓存**：
    // shared_preferences 在 Android 上是全量读进内存的 XML，
    // 塞几十 MB 进去会让每次读写都付出代价。
    final TextbookApi textbookApi = TextbookApi(
      apiClient: apiClient,
      logger: logger,
    );

    final CatalogFileStore catalogFiles = CatalogFileStore(paths: paths);
    final CatalogRepository catalogRepository = CatalogRepository(
      downloader: CatalogApi(
        apiClient: apiClient,
        failureMapper: const DefaultFailureMapper(),
        logger: logger,
      ),
      fileStore: catalogFiles,
      logger: logger,
    );

    // ---------- 下载 ----------
    // 与平台客户端分开：下载走二进制流，不该进缓存；重试由下载器自己
    // 按镜像轮换与限流退避统一负责，两套重试叠加会打乱配额节奏。
    final Dio downloadDio = DioFactory(
      logger: logger,
      cache: cache,
      policyRegistry: policyRegistry,
      credentialProvider: authSession,
      signer: NdAuthSigner(),
    ).createDownloadClient(HttpConfig.forEnvironment(env));

    final DownloadManager downloadManager = DownloadManager(
      client: downloadDio,
      paths: paths,
      logger: logger,
      // 用回调而不是快照：用户可能在下载过程中登录，之后的任务应当走私有域。
      isLoggedIn: () => authSession.isLoggedIn,
    );

    // ---------- 连通性 ----------
    final ConnectivityService connectivity = ConnectivityService(
      logger: logger,
    );
    await connectivity.start();

    // ---------- 启动配置 ----------
    final ThemeMode themeMode = await _readThemeMode(preferences);
    final Locale? locale = await _readLocale(preferences);

    // ---------- 后台维护 ----------
    // 清理过期缓存不阻塞启动，交给后台执行。
    unawaited(cache.evictExpired());

    logger.i('依赖装配完成（${env.label}，缓存：${cache.storeName}）');

    return AppDependencies(
      logger: logger,
      preferences: preferences,
      secureStorage: secureStorage,
      paths: paths,
      cache: cache,
      cachePolicyRegistry: policyRegistry,
      dio: dio,
      apiClient: apiClient,
      textbookApi: textbookApi,
      catalogRepository: catalogRepository,
      downloadManager: downloadManager,
      connectivity: connectivity,
      authSession: authSession,
      initialThemeMode: themeMode,
      initialLocale: locale,
    );
  }

  /// 释放需要显式关闭的资源。
  Future<void> dispose() async {
    await connectivity.dispose();
    dio.close(force: true);
  }

  // ==================== 内部实现 ====================

  /// 初始化 `intl` 的日期本地化数据与默认语言。
  ///
  /// 不做这一步，`DateFormat('yyyy年M月d日')` 会因为没有语言数据而抛异常。
  static Future<void> _initializeDateFormats() async {
    await initializeDateFormatting('zh_CN');
    Intl.defaultLocale = 'zh_CN';
  }

  /// 读取持久化的主题模式，非法值一律回落到跟随系统。
  static Future<ThemeMode> _readThemeMode(KeyValueStore store) async {
    final String? raw = await store.readString(StorageKeys.themeMode);
    return ThemeMode.values.firstWhere(
      (ThemeMode mode) => mode.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  /// 读取持久化的语言。
  static Future<Locale?> _readLocale(KeyValueStore store) async {
    final String? raw = await store.readString(StorageKeys.locale);
    return raw == null || raw.isEmpty ? null : Locale(raw);
  }
}
