// 真实链路验证：对着**线上平台**跑一遍"拉取 → 解析 → 建索引"。
//
// 为什么放在 `tool/` 而不是 `test/`：它会发真实网络请求，耗时以分钟计，
// 还会受网络波动影响。放进默认测试套件会让 `flutter test` 变慢且不稳定。
//
// 运行方式：
// ```bash
// flutter test tool/verify_catalog_test.dart
// ```
//
// 它同时是一份可复用的诊断脚本：平台接口变动时，先跑它，
// 能立刻看出是"探测版本失败""分片下载失败"还是"解析后条目数为 0"。

import 'dart:io';

import 'package:chinese_textbooks/apis/apis.dart';
import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/pages/browse/browse_provider.dart';
import 'package:chinese_textbooks/pages/browse/browse_row.dart';
import 'package:chinese_textbooks/services/cache/cache.dart';
import 'package:chinese_textbooks/services/catalog/catalog.dart';
import 'package:chinese_textbooks/services/http/http.dart';
import 'package:chinese_textbooks/services/logger/app_logger.dart';
import 'package:chinese_textbooks/services/storage/app_paths.dart';
import 'package:chinese_textbooks/utils/utils.dart';
import 'package:chinese_textbooks/values/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late AppPaths paths;
  late CatalogRepository repository;

  // 整个文件共用一个沙箱：第二个用例要验证的正是"第一次下载留下的
  // ETag 与分片文件能不能让第二次跳过下载"，各用例独立目录就验不到了。
  setUpAll(() async {
    // `flutter_test` 默认把所有 HTTP 请求拦截成 400，这里恢复真实网络。
    HttpOverrides.global = null;

    sandbox = await Directory.systemTemp.createTemp('nd_catalog_verify');
    paths = AppPaths.forRoot(sandbox);
    await paths.ensureCreated();

    // 关掉逐请求日志：验证脚本自己会打印阶段与统计，请求级日志只会淹没结论。
    final AppLogger logger = AppLogger(verbose: false);
    final DioFactory factory = DioFactory(
      logger: logger,
      cache: CacheManager(
        store: MemoryCacheStore(),
        transientStore: MemoryCacheStore(),
        logger: logger,
      ),
      policyRegistry: CachePolicyRegistry(),
      credentialProvider: const AnonymousCredentialProvider(),
      signer: NdAuthSigner(),
    );
    final ApiClient client = ApiClient(
      dio: factory.createPlatformClient(
        HttpConfig.forEnvironment(AppEnvironment.dev),
      ),
      failureMapper: const DefaultFailureMapper(),
      logger: logger,
    );

    repository = CatalogRepository(
      downloader: CatalogApi(
        apiClient: client,
        failureMapper: const DefaultFailureMapper(),
        logger: logger,
      ),
      fileStore: CatalogFileStore(paths: paths),
      logger: logger,
    );
  });

  tearDownAll(() async {
    // 加 ND_KEEP_SANDBOX=1 时保留沙箱并打印路径，便于把目录数据
    // 复制到应用的真实数据目录里做手工验证。
    if (Platform.environment['ND_KEEP_SANDBOX'] == '1') {
      stdout.writeln('  沙箱保留在：${sandbox.path}');
      return;
    }
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('首次全量拉取并构建索引', () async {
    final List<CatalogProgress> stages = <CatalogProgress>[];

    final result = await repository.refreshIfNeeded(
      onProgress: (CatalogProgress progress) {
        if (stages.isEmpty || stages.last.stage != progress.stage) {
          stages.add(progress);
          stdout.writeln('  阶段：${progress.stage.name}');
        }
      },
    );

    switch (result) {
      case Success<CatalogIndex?>(:final CatalogIndex? data):
        expect(data, isNotNull, reason: '首次拉取必须返回索引');
        // 空断言之后再解包：`data!` 会把局部变量提升为非空类型。
        data!;

        stdout.writeln('  教材总数：${data.length}');
        stdout.writeln('  顶层分类：${data.roots.map((n) => n.label).join(' / ')}');
        stdout.writeln(
          '  筛选维度：${data.facets.map((CatalogFacet f) => f.label).join(' → ')}',
        );

        // 诊断：筛选维度。
        for (final CatalogFacet facet in data.facets) {
          final String top = facet.options
              .take(4)
              .map((CatalogLevelOption o) => '${o.label}(${o.bookCount})')
              .join(' ');
          stdout.writeln(
            '  [${facet.dimensionId}] ${facet.label}'
            '（${facet.options.length} 项）: $top',
          );
        }

        // 诊断：多少条目没能进索引，以及原因。
        await _reportSkipped(paths, data.length);

        // 平台当前约有三千余本；给一个宽松下界，避免把测试绑死在精确数字上。
        expect(data.length, greaterThan(2500));
        expect(data.roots, isNotEmpty);
        expect(data.facets.length, greaterThanOrEqualTo(4));

        // 抽查一本：能查到、有分类路径、页数之外的基本字段齐全。
        final Textbook sample = data.items.first;
        expect(sample.title, isNotEmpty);
        expect(data.categoryPathOf(sample), isNotEmpty);
        expect(data.byId(sample.id), isNotNull);

        // 搜索与筛选至少能跑通且不抛异常。
        final List<Textbook> searched = data.filterAndSearch(
          const CatalogFilter(),
          '语文',
        );
        stdout.writeln('  搜索「语文」命中：${searched.length}');
        expect(searched, isNotEmpty);

        // 按维度筛选跑一遍。
        final CatalogFacet stage = data.facets.firstWhere(
          (CatalogFacet facet) => facet.dimensionId == 'zxxxd',
        );
        final List<Textbook> byStage = data.filterAndSearch(
          const CatalogFilter().toggle('zxxxd', stage.options.first.tagId),
          '',
        );
        stdout.writeln(
          '  按学段「${stage.options.first.label}」筛选：${byStage.length}',
        );
        expect(byStage, isNotEmpty);
        expect(byStage.length, lessThan(data.length));

        // 三态选择跑一遍。
        final CatalogSelection selection = CatalogSelection(index: data);
        selection.setNode(data.roots.first.id, selected: true);
        expect(selection.selectedCount, greaterThan(0));
        expect(
          selection.stateOf(data.roots.first.id),
          SelectionState.all,
        );

        // 目录页的浏览逻辑也对着真实数据跑一遍：
        // 树的拍平、展开全部、勾选与筛选解耦。
        final BrowseProvider browse = BrowseProvider(index: data);
        addTearDown(browse.dispose);

        final int collapsedRows = browse.rows.length;
        expect(collapsedRows, data.roots.length, reason: '默认全部折叠');

        browse.expandAll();
        final int expandedRows = browse.rows.length;
        final int bookRows = browse.rows.whereType<BrowseBookRow>().length;
        stdout.writeln(
          '  树：折叠 $collapsedRows 行 → 展开 $expandedRows 行（其中教材 $bookRows 行）',
        );
        expect(bookRows, data.length, reason: '展开全部后每本教材都应可见');

        browse
          ..setQuery('语文')
          ..toggleAllVisible();
        final int picked = browse.selection.selectedCount;
        stdout.writeln('  搜索「语文」后全选：$picked 本');

        browse
          ..clearAllFilters()
          ..setQuery('数学');
        expect(
          browse.selection.selectedCount,
          picked,
          reason: '换筛选条件不该影响已勾选',
        );
        stdout.writeln('  换条件后仍保持：${browse.selection.selectedCount} 本');

        browse.collapseAll();
        expect(browse.rows.length, collapsedRows);

      case Failure<CatalogIndex?>(:final AppFailure failure):
        fail('拉取失败：${failure.message}（${failure.typeName}）');
    }

    expect(
      stages.map((CatalogProgress p) => p.stage),
      contains(CatalogStage.ready),
    );
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('二次拉取命中 ETag，不重复下载', () async {
    // 核心断言：刚刚全量下载过，紧接着再探测应当判定「未变化」——
    // 这正是分片级增量更新成立与否的判据。
    final first = await repository.refreshIfNeeded();
    expect(first.isSuccess, isTrue, reason: '探测应当成功');
    expect(
      first.dataOrNull,
      isNull,
      reason: 'ETag 未变时应当返回 null，否则每次启动都会重下全部 40MB',
    );

    final Stopwatch stopwatch = Stopwatch()..start();
    final second = await repository.refreshIfNeeded();
    stopwatch.stop();
    stdout.writeln('  二次探测耗时：${stopwatch.elapsedMilliseconds}ms');
    if (second.dataOrNull != null) {
      // 不当作失败：CDN 偶尔会对同一 ETag 回 200 而不是 304，
      // 那会白下一次分片，但不是代码问题。这里只记录，便于观察频率。
      stdout.writeln('  ⚠️ 二次探测判定有更新（多为 CDN 未回 304）');
    }

    // 只读本地也应当能拿到完整的索引。
    final local = await repository.loadLocal();
    expect(local.isSuccess, isTrue);
    expect(local.dataOrNull?.length, greaterThan(2500));
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// 报告有多少条目没能进索引、以及卡在哪一步。
///
/// 平台的标签树**并不包含书目引用到的全部节点**（实测「册次」一层有一半
/// 在树里找不到），所以条目会在中途停下、挂到更浅的节点上。
/// 这个数字平时应当是小的；一旦明显变大，说明标签树与书目数据的版本错开了。
Future<void> _reportSkipped(AppPaths paths, int indexed) async {
  final Directory shardDir = Directory('${paths.catalog.path}/shards');
  if (!shardDir.existsSync()) {
    return;
  }
  int rows = 0;
  int tooShallow = 0;
  for (final FileSystemEntity entity in shardDir.listSync()) {
    if (entity is! File) {
      continue;
    }
    final List<List<String>>? decoded = CatalogShardCodec.decode(
      await entity.readAsString(),
    );
    for (final List<String> row in decoded ?? const <List<String>>[]) {
      rows++;
      if (row[CatalogColumn.tagPath].split('/').length < 3) {
        tooShallow++;
      }
    }
  }
  stdout.writeln(
    '  分片条目共 $rows 条，进索引 $indexed 条，未进索引 ${rows - indexed} 条（路径过短 $tooShallow 条）',
  );
}
