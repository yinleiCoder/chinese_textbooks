import 'dart:io';

import 'package:chinese_textbooks/apis/apis.dart';
import 'package:chinese_textbooks/pages/library/library.dart';
import 'package:chinese_textbooks/providers/providers.dart';
import 'package:chinese_textbooks/services/services.dart';
import 'package:chinese_textbooks/utils/utils.dart';
import 'package:chinese_textbooks/values/values.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../services/catalog_fixture.dart';
import '../services/memory_store.dart';

/// 夹具里 `book-a1` 的书名。
const String kBookTitleA1 = '义务教育教科书·语文一年级上册';

/// 内存键值存储：`PreferencesStore` 要走平台通道，测试里用不了。
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

void main() {
  late Directory sandbox;
  late AppPaths paths;
  late AppLogger logger;
  late MemoryStore store;
  late CatalogProvider catalog;
  late LibraryProvider library;
  late DownloadProvider downloads;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('library_group_test');
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
  });

  tearDown(() async {
    downloads.dispose();
    library.dispose();
    catalog.dispose();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        // 与 main.dart 保持一致：生产走的是 ensureScreenSize + FutureBuilder
        // 那条分支，也会在度量变化时手动遍历元素树 markNeedsBuild。
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
          child: MaterialApp(theme: AppTheme.light, home: const LibraryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 模拟软键盘弹出／收起：真机上"输入新分组名"必然会走到这里，
  /// 而"选一个已有分组"不会——这正是两条路径的实质差别。
  Future<void> setIme(WidgetTester tester, {required bool open}) async {
    tester.view.viewInsets = open
        ? const FakeViewPadding(bottom: 900)
        : FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 长按进选择模式 → 点"分组到" → 输入名字 → 确认。
  ///
  /// **这里测不到分组角标真的画出来。** `LibraryProvider.assignGroup` 落盘后
  /// 会 `refresh()` 重扫一遍磁盘，而 `flutter_test` 跑在 FakeAsync 里，
  /// `dart:io` 的真实异步不会完成（试过 `runAsync` 交替放行也没用），
  /// 于是"落盘 → 重扫 → 重建"这一步在测试里根本不发生。
  /// 能测的是：对话框架构、退场动画、退出选择模式、SnackBar 这条路径不炸。
  /// 要覆盖重建那一步，得把整理信息的保存与书架重扫解耦（见 provider 注释）。
  Future<void> createGroup(
    WidgetTester tester,
    String name, {
    bool withIme = false,
  }) async {
    await tester.longPress(find.text(kBookTitleA1));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, AppStrings.libraryGroup));
    await tester.pumpAndSettle();

    if (withIme) {
      await setIme(tester, open: true);
    }

    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, AppStrings.confirm));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    if (withIme) {
      await setIme(tester, open: false);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('新建第一个分组（书上没有阅读进度）', (WidgetTester tester) async {
    await pumpLibrary(tester);
    expect(find.text(kBookTitleA1), findsOneWidget);

    await createGroup(tester, '一年级上');

    expect(tester.takeException(), isNull);
    expect(library.groupOf(kBookA1), '一年级上');
  });

  group('书上带阅读进度角标', () {
    setUp(() async {
      // 角标在场时，分组角标是插在 Stack 子节点**中间**的。
      await store.writeString(LibraryProvider.progressKey(kBookA1), '12');
      await library.load(index: catalog.index);
    });

    testWidgets('新建第一个分组', (WidgetTester tester) async {
      await pumpLibrary(tester);
      expect(find.text(kBookTitleA1), findsOneWidget);

      await createGroup(tester, '一年级上');

      expect(tester.takeException(), isNull);
      expect(library.groupOf(kBookA1), '一年级上');
    });
  });

  group('已有分组', () {
    setUp(() async {
      await library.assignGroup(<String>{kBookA1}, '旧分组');
      await library.load(index: catalog.index);
    });

    testWidgets('再建一个新分组', (WidgetTester tester) async {
      await pumpLibrary(tester);
      expect(find.text(kBookTitleA1), findsOneWidget);

      await createGroup(tester, '新分组');

      expect(tester.takeException(), isNull);
      expect(library.groupOf(kBookA1), '新分组');
    });

    testWidgets('新建分组（期间软键盘弹出又收起）', (WidgetTester tester) async {
      await pumpLibrary(tester);
      expect(find.text(kBookTitleA1), findsOneWidget);

      await createGroup(tester, '新分组', withIme: true);

      expect(tester.takeException(), isNull);
      expect(library.groupOf(kBookA1), '新分组');
    });
  });

  testWidgets('新建第一个分组（期间软键盘弹出又收起）', (WidgetTester tester) async {
    await pumpLibrary(tester);
    expect(find.text(kBookTitleA1), findsOneWidget);

    await createGroup(tester, '一年级上', withIme: true);

    expect(tester.takeException(), isNull);
    expect(library.groupOf(kBookA1), '一年级上');
  });
}
