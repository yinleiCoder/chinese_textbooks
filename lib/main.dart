import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'apis/apis.dart';
import 'pages/pages.dart';
import 'providers/providers.dart';
import 'services/services.dart';
import 'values/values.dart';

/// 应用入口。
///
/// 启动顺序是有依赖关系的，不能调换：
/// 1. `ensureInitialized` —— 存储与安全存储都要走平台通道；
/// 2. `AppDependencies.create` —— 装配全部依赖，并读出上次的主题与语言；
/// 3. `runApp` —— 首帧就用正确的主题渲染，避免"先亮后暗"的闪烁。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppDependencies dependencies = await AppDependencies.create();

  runApp(ChineseTextbooksApp(dependencies: dependencies));
}

/// 应用根组件。
///
/// 采用 [StatefulWidget] 只为一件事：持有 `GoRouter` 与依赖容器的生命周期，
/// 在应用销毁时把它们释放掉。业务状态一律在 `providers/` 里，
/// 这里不存放任何业务数据。
final class ChineseTextbooksApp extends StatefulWidget {
  const ChineseTextbooksApp({required this.dependencies, super.key});

  /// 已装配好的依赖容器。
  final AppDependencies dependencies;

  @override
  State<ChineseTextbooksApp> createState() => _ChineseTextbooksAppState();
}

class _ChineseTextbooksAppState extends State<ChineseTextbooksApp> {
  late final GoRouter _router = AppNavigator.create(
    observers: <NavigatorObserver>[
      AppNavigatorObserver(logger: widget.dependencies.logger),
    ],
    debugLogDiagnostics: !AppConfig.environment.isProduction,
  );

  @override
  void dispose() {
    _router.dispose();
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // 元素类型由 provider 包自行推断，这里不写显式类型参数，
      // 否则会与 `nested` 的内部类型产生耦合。
      providers: [
        // ---------- 基础设施：整个应用生命周期内复用同一实例 ----------
        Provider<AppDependencies>.value(value: widget.dependencies),
        Provider<AppLogger>.value(value: widget.dependencies.logger),
        Provider<CacheManager>.value(value: widget.dependencies.cache),
        Provider<ApiClient>.value(value: widget.dependencies.apiClient),
        Provider<TextbookApi>.value(value: widget.dependencies.textbookApi),
        // 书架要按目录 id 扫描本地文件，阅读器要定位 PDF 路径，
        // 两者都需要它。
        Provider<AppPaths>.value(value: widget.dependencies.paths),
        Provider<ConnectivityService>.value(
          value: widget.dependencies.connectivity,
        ),

        // ---------- 状态：由 Provider 负责创建与销毁 ----------
        // 初始值已在启动阶段读出，因此这里不需要异步加载，
        // 也就不会出现"首帧用了默认主题、片刻后才切换"的跳动。
        ChangeNotifierProvider<AppThemeProvider>(
          create: (BuildContext _) => AppThemeProvider(
            store: widget.dependencies.preferences,
            logger: widget.dependencies.logger,
            initialMode: widget.dependencies.initialThemeMode,
          ),
        ),
        ChangeNotifierProvider<AppLocaleProvider>(
          create: (BuildContext _) => AppLocaleProvider(
            store: widget.dependencies.preferences,
            logger: widget.dependencies.logger,
            initialLocale: widget.dependencies.initialLocale,
          ),
        ),
        ChangeNotifierProvider<AppConnectivityProvider>(
          create: (BuildContext _) => AppConnectivityProvider(
            service: widget.dependencies.connectivity,
          ),
        ),
        // 登录态由组合根创建（网络层、下载器都要用同一个实例），
        // 这里只是把它接进 widget 树。
        ChangeNotifierProvider<AuthSessionProvider>.value(
          value: widget.dependencies.authSession,
        ),
        // 下载队列也是跨页面共享的：目录页入队、下载页看进度、详情页看单本。
        ChangeNotifierProvider<DownloadProvider>(
          create: (BuildContext _) => DownloadProvider(
            manager: widget.dependencies.downloadManager,
            textbookApi: widget.dependencies.textbookApi,
            logger: widget.dependencies.logger,
            isAlreadyDownloaded: (String id) => widget
                .dependencies
                .paths
                .pdfDirectory
                .listSync()
                .any((FileSystemEntity e) => e.path.endsWith('$id.pdf')),
          ),
        ),
        // 书架与阅读进度：目录页、书架、阅读器都要用。
        ChangeNotifierProvider<LibraryProvider>(
          create: (BuildContext _) => LibraryProvider(
            paths: widget.dependencies.paths,
            store: widget.dependencies.preferences,
            logger: widget.dependencies.logger,
          ),
        ),
        // 目录状态是跨页面共享的：目录树、书架、下载、设置都要读它。
        // 加载由 HomeShell 在首帧后触发（见该文件注释）。
        ChangeNotifierProvider<CatalogProvider>(
          create: (BuildContext _) => CatalogProvider(
            repository: widget.dependencies.catalogRepository,
            logger: widget.dependencies.logger,
          ),
        ),
      ],
      child: ScreenUtilInit(
        // 设计稿尺寸必须与 UI 稿一致，它是所有 .w/.h/.r/.sp 的换算基准。
        designSize: AppConfig.designSize,
        // 分屏 / 折叠屏下按实际可用区域换算，而不是整块屏幕。
        splitScreenMode: true,
        // 字号取宽高缩放比的较小值，避免在长屏手机上字被放大得过大。
        minTextAdapt: true,
        ensureScreenSize: true,
        builder: (BuildContext context, Widget? child) =>
            _AppView(router: _router),
      ),
    );
  }
}

/// 应用外壳：把状态接到 [MaterialApp.router] 上。
///
/// 单独抽出来是为了让 `context.watch` 有一个**位于 Provider 之下**的
/// 构建上下文——在 `_ChineseTextbooksAppState.build` 里 watch 是拿不到
/// 自己刚创建的 Provider 的。
final class _AppView extends StatelessWidget {
  const _AppView({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final AppThemeProvider themeProvider = context.watch<AppThemeProvider>();
    final AppLocaleProvider localeProvider = context.watch<AppLocaleProvider>();

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.themeMode,
      locale: localeProvider.locale,
      supportedLocales: AppLocaleProvider.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        // 限制系统字体缩放范围：用户把系统字号拉到最大时，
        // 无限制跟随会撑破卡片与按钮布局；限制后依然可读，但不会错位。
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
