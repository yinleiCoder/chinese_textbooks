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

/// 书架**画出来的样子**：分区表头在不在、每区里有几本书。
///
/// 与 `library_group_test.dart` 不同，这里**不测"分组"这个动作**，只测渲染：
/// 数据在 pump 之前就摆好，因此不需要等 `assignGroup` 落盘后的那次磁盘重扫，
/// 也就绕开了 FakeAsync 跑不完 `dart:io` 异步的限制。
void main() {
  late Directory sandbox;
  late AppPaths paths;
  late LibraryProvider library;
  late CatalogProvider catalog;
  late DownloadProvider downloads;

  /// 搭好一个书架。
  ///
  /// 整理信息必须在 `testWidgets` **之外**写好：`assignGroup` 落盘后要重扫磁盘，
  /// 而 `testWidgets` 跑在 FakeAsync 里，真实的 `dart:io` 异步永远不会完成，
  /// 在测试体里调用它会直接挂住。
  Future<void> setUpLibrary({required bool grouped}) async {
    sandbox = await Directory.systemTemp.createTemp('library_shelf_render');
    paths = AppPaths.forRoot(sandbox);
    await paths.ensureCreated();

    for (final String id in <String>[
      kBookA1,
      kBookA2,
      kBookA3,
      kBookB1,
      kBookC1,
    ]) {
      await File('${paths.pdfDirectory.path}${Platform.pathSeparator}$id.pdf')
          .writeAsString('pdf');
    }

    final AppLogger logger = AppLogger(verbose: false);
    final MemoryStore store = MemoryStore();
    catalog = CatalogProvider(
      repository: CatalogRepository(
        downloader: _NoopDownloader(),
        fileStore: CatalogFileStore(paths: paths),
        logger: logger,
      ),
      logger: logger,
    );

    library = LibraryProvider(paths: paths, store: store, logger: logger);
    // 先摆整理信息，再 load——顺序反了的话 load 会先扫一遍空书架。
    if (grouped) {
      await library.assignGroup(<String>{kBookA1, kBookA3}, '语文');
      await library.togglePin(<String>{kBookA1});
    }
    await library.load(index: buildCatalogIndex());

    downloads = DownloadProvider(
      manager: DownloadManager(
        client: Dio(),
        paths: paths,
        logger: logger,
        isLoggedIn: () => false,
      ),
      textbookApi: TextbookApi(
        apiClient: ApiClient(
          dio: Dio(),
          failureMapper: const DefaultFailureMapper(),
          logger: logger,
        ),
        logger: logger,
      ),
      logger: logger,
      isAlreadyDownloaded: (String _) => true,
    );
  }

  tearDown(() async {
    downloads.dispose();
    library.dispose();
    catalog.dispose();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  /// 视口。默认的 800×600 放不下多个分区，而 `SliverGrid` 是懒构建的——
  /// 屏幕外的分区根本不会被 build，`find` 自然找不到。给大一点，
  /// 断言才是"画没画"而不是"滚没滚到"；测手机宽度时再单独调小。
  const Size kWideViewport = Size(1400, 3000);

  Future<void> pumpLibrary(
    WidgetTester tester, {
    Size viewport = kWideViewport,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: AppConfig.designSize,
        splitScreenMode: true,
        minTextAdapt: true,
        ensureScreenSize: true,
        builder: (BuildContext context, Widget? _) => MultiProvider(
          providers: [
            Provider<AppLogger>.value(value: AppLogger(verbose: false)),
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

  group('已分组', () {
    setUp(() => setUpLibrary(grouped: true));

    testWidgets('置顶区与分组区都画出表头', (WidgetTester tester) async {
      await pumpLibrary(tester);

      expect(find.text(AppStrings.libraryPin), findsOneWidget, reason: '置顶区表头');
      expect(find.text('语文'), findsWidgets, reason: '分组区表头');
      expect(
        find.text(AppStrings.libraryUngrouped),
        findsOneWidget,
        reason: '未分组表头',
      );

      // 每区的本数：置顶 1 本、语文 1 本（a1 被置顶挪走了）、未分组 3 本。
      expect(find.text(AppStrings.librarySectionCount(1)), findsNWidgets(2));
      expect(find.text(AppStrings.librarySectionCount(3)), findsOneWidget);
    });
  });

  group('没有分组', () {
    setUp(() => setUpLibrary(grouped: false));

    testWidgets('不出表头，与老书架长得一样', (WidgetTester tester) async {
      await pumpLibrary(tester);

      expect(find.text(AppStrings.libraryUngrouped), findsNothing);
      expect(find.text(AppStrings.libraryPin), findsNothing);
      expect(find.text('语文'), findsNothing);
    });
  });

  group('网格列数', () {
    setUp(() => setUpLibrary(grouped: true));

    /// 取第一片书网格的列数。
    int columnsOf(WidgetTester tester) {
      final SliverGrid grid = tester.widget<SliverGrid>(
        find.byType(SliverGrid).first,
      );
      final SliverGridDelegateWithFixedCrossAxisCount delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return delegate.crossAxisCount;
    }

    testWidgets('360dp 手机上排 2 列', (WidgetTester tester) async {
      // 老实现用的是"每列最大 320"，336 / (320 + 16) 正好 1.0，
      // 向上取整就是 1 列——手机上书一排只摆一本。
      await pumpLibrary(tester, viewport: const Size(360, 800));

      expect(columnsOf(tester), 2);
    });

    testWidgets('宽窗口列数随宽度增加', (WidgetTester tester) async {
      await pumpLibrary(tester, viewport: const Size(1400, 3000));

      expect(columnsOf(tester), greaterThan(2));
    });
  });

  group('置顶按钮', () {
    setUp(() => setUpLibrary(grouped: true));

    testWidgets('选中的书已置顶时，按钮变成「取消置顶」', (WidgetTester tester) async {
      await pumpLibrary(tester);

      // 长按进选择模式，这一下顺带就把那本**已经置顶**的书勾上了
      // （再点一次反倒是取消勾选）。
      await tester.longPress(find.text(kBookTitleA1));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.libraryPin), findsOneWidget, reason: '分区表头');
      expect(find.text(AppStrings.libraryUnpin), findsOneWidget, reason: '操作按钮');
    });
  });
}

/// 这个测试不碰目录下载（`catalog` 从不 `initialize`），因此任何一次调用
/// 都是测试写错了——直接炸掉，好过静默返回假数据。
final class _NoopDownloader implements CatalogDownloader {
  @override
  Future<Result<CatalogVersionInfo>> fetchVersion() =>
      throw UnimplementedError('本测试不下载目录');

  @override
  Future<Result<DownloadOutcome>> downloadPart(
    Uri url,
    File target, {
    String? etag,
    PartProgressCallback? onProgress,
  }) => throw UnimplementedError('本测试不下载目录');

  @override
  Future<Result<DownloadOutcome>> downloadTagTree(
    File target, {
    String? etag,
  }) => throw UnimplementedError('本测试不下载目录');
}
