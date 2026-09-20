import 'dart:io';

import 'package:chinese_textbooks/pages/browse/browse.dart';
import 'package:chinese_textbooks/providers/catalog_provider.dart';
import 'package:chinese_textbooks/services/catalog/catalog.dart';
import 'package:chinese_textbooks/services/logger/app_logger.dart';
import 'package:chinese_textbooks/services/storage/app_paths.dart';
import 'package:chinese_textbooks/utils/utils.dart';
import 'package:chinese_textbooks/values/values.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../services/catalog_fixture.dart';

/// 用夹具数据冒充平台分片的下载器。
///
/// 这样整条链路都是真的：请求 → 解析（isolate）→ 列式落盘 → 建索引 → 渲染，
/// 只有"网络"这一层是假的。
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
  late CatalogProvider catalog;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('browse_page_test');
    final AppPaths paths = AppPaths.forRoot(sandbox);
    await paths.ensureCreated();
    final AppLogger logger = AppLogger(verbose: false);

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
  });

  tearDown(() async {
    catalog.dispose();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // 必须包在 ScreenUtilInit 里：`AppTheme.light` 会经 AppDimens 触到
    // ScreenUtil 的全局状态，未初始化时直接抛异常。
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: AppConfig.designSize,
        builder: (BuildContext context, Widget? _) =>
            ChangeNotifierProvider<CatalogProvider>.value(
              value: catalog,
              child: MaterialApp(
                theme: AppTheme.light,
                home: const BrowsePage(),
              ),
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('目录数据就绪后渲染分类树', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(catalog.index?.length, 5);
    expect(find.text(AppStrings.resultCount(5)), findsOneWidget);
    // 顶层是两个学段。
    expect(find.text('小学'), findsOneWidget);
    expect(find.text('初中'), findsOneWidget);
    expect(find.text(AppStrings.expandAll), findsOneWidget);
  });

  testWidgets('展开后出现子分类', (WidgetTester tester) async {
    await pumpPage(tester);

    // 点分类行是**勾选**，展开要点前面的箭头——三态树的通行交互。
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('语文'), findsOneWidget);
    expect(find.text('数学'), findsOneWidget);
  });

  testWidgets('勾选分类后底部出现操作条', (WidgetTester tester) async {
    await pumpPage(tester);

    // 操作条在没勾选时不该占位。
    expect(find.textContaining('已选'), findsNothing);

    // 点复选框勾选整个分类。整行也可点，效果相同。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.selectedCount(4)), findsOneWidget);
    expect(find.text(AppStrings.downloadSelected), findsOneWidget);
    expect(find.text(AppStrings.selectAllResults), findsOneWidget);
  });

  testWidgets('清空勾选后操作条消失', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('已选'), findsOneWidget);

    // 次要按钮在横向滚动区里，先滚到可见位置再点。
    final Finder clearButton = find.widgetWithText(
      TextButton,
      AppStrings.clearSelection,
    );
    await tester.ensureVisible(clearButton);
    await tester.pumpAndSettle();
    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('已选'), findsNothing);
  });

  testWidgets('搜索后切换到扁平结果列表', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), '语文');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text(AppStrings.resultCount(4)), findsOneWidget);
    expect(find.textContaining('义务教育教科书·语文一年级上册'), findsWidgets);
  });
}
