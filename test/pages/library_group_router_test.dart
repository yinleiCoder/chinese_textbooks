import 'dart:io';

import 'package:chinese_textbooks/apis/apis.dart';
import 'package:chinese_textbooks/pages/app_navigator.dart';
import 'package:chinese_textbooks/providers/providers.dart';
import 'package:chinese_textbooks/services/services.dart';
import 'package:chinese_textbooks/utils/utils.dart';
import 'package:chinese_textbooks/values/values.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/catalog_fixture.dart';
import '../services/memory_store.dart';

/// 夹具里 `book-a1` 的书名。
const String kBookTitleA1 = '义务教育教科书·语文一年级上册';

final class _FixtureDownloader implements CatalogDownloader {
  @override
  Future<Result<CatalogVersionInfo>> fetchVersion() async => Success(
    CatalogVersionInfo(
      partUrls: <Uri>[Uri.parse('https://example.test/part_0.json')],
    ),
  );

  @override
  Future<Result<DownloadOutcome>> downloadPart(
    Uri url,
    File target, {
    String? etag,
    PartProgressCallback? onProgress,
  }) async {
    await target.parent.create(recursive: true);
    await target.writeAsString(buildRawBooksJson());
    return const Success<DownloadOutcome>(DownloadOutcome.downloaded('"p0"'));
  }

  @override
  Future<Result<DownloadOutcome>> downloadTagTree(
    File target, {
    String? etag,
  }) async {
    await target.parent.create(recursive: true);
    await target.writeAsString(buildRawTagTreeJson());
    return const Success<DownloadOutcome>(DownloadOutcome.downloaded('"t0"'));
  }
}

/// 与 main.dart 同构：**真实的 go_router**（AppNavigator.create）+ 外壳，
/// 只把平台相关的装配换成测试替身。
///
/// 之所以要这一份：分组对话框是 `showDialog` 推到**根 Navigator** 上的，
/// 而根 Navigator 归 go_router 管。只挂 `MaterialApp(home: LibraryPage())`
/// 的测试跑不到这条路径。
void main() {
  late Directory sandbox;
  late AppPaths paths;
  late AppLogger logger;
  late MemoryStore store;
  late CatalogProvider catalog;
  late LibraryProvider library;
  late DownloadProvider downloads;
  late GoRouter router;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('library_group_router');
    paths = AppPaths.forRoot(sandbox);
    await paths.ensureCreated();
    logger = AppLogger(verbose: false);
    store = MemoryStore();

    await File(
      '${paths.pdfDirectory.path}${Platform.pathSeparator}$kBookA1.pdf',
    ).writeAsString('pdf');

    catalog = CatalogProvider(
      repository: CatalogRepository(
        downloader: _FixtureDownloader(),
        fileStore: CatalogFileStore(paths: paths),
        logger: logger,
      ),
      logger: logger,
    );
    await catalog.initialize();
    await catalog.download();

    library = LibraryProvider(paths: paths, store: store, logger: logger);
    await library.load(index: catalog.index);

    final ApiClient apiClient = ApiClient(
      dio: Dio(),
      failureMapper: const DefaultFailureMapper(),
      logger: logger,
    );
    downloads = DownloadProvider(
      manager: DownloadManager(
        client: Dio(),
        paths: paths,
        logger: logger,
        isLoggedIn: () => false,
      ),
      textbookApi: TextbookApi(apiClient: apiClient, logger: logger),
      logger: logger,
      isAlreadyDownloaded: (String _) => true,
    );

    router = AppNavigator.create(
      observers: <NavigatorObserver>[
        AppNavigatorObserver(logger: logger),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    downloads.dispose();
    library.dispose();
    catalog.dispose();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: AppConfig.designSize,
        splitScreenMode: true,
        minTextAdapt: true,
        ensureScreenSize: true,
        builder: (BuildContext context, Widget? _) => MultiProvider(
          providers: [
            Provider<AppLogger>.value(value: logger),
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<CatalogProvider>.value(value: catalog),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            routerConfig: router,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (BuildContext context, Widget? child) =>
                MediaQuery.withClampedTextScaling(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.3,
                  child: child ?? const SizedBox.shrink(),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 长按进选择模式 → 点"分组到" → 输入名字 → 确认。
  Future<void> createGroup(WidgetTester tester, String name) async {
    await tester.longPress(find.text(kBookTitleA1));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, AppStrings.libraryGroup));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, AppStrings.confirm));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('真路由下：新建第一个分组', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.text(kBookTitleA1), findsOneWidget);

    await createGroup(tester, '一年级上');

    expect(tester.takeException(), isNull);
    expect(library.groupOf(kBookA1), '一年级上');
  });

  testWidgets('真路由下：取消对话框', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.text(kBookTitleA1), findsOneWidget);

    await tester.longPress(find.text(kBookTitleA1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, AppStrings.libraryGroup));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, AppStrings.cancel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('分组到'), findsOneWidget);
  });
}
