import 'dart:convert';
import 'dart:io';

import 'package:chinese_textbooks/providers/providers.dart';
import 'package:chinese_textbooks/services/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/catalog_fixture.dart';
import '../services/memory_store.dart';

/// 夹具里所有书名共有的前缀。
const String _titlePrefix = '义务教育教科书·';

/// 书架**分区**的行为。
///
/// 只测 provider，不建 widget 树：分区的组成与顺序是纯粹的数据问题，
/// 而 widget 测试跑在 FakeAsync 里，`assignGroup` 落盘后的那次磁盘重扫
/// 根本不会完成（详见 `library_group_test.dart` 的说明）。
void main() {
  late Directory sandbox;
  late AppPaths paths;
  late LibraryProvider library;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('library_sections');
    paths = AppPaths.forRoot(sandbox);
    await paths.ensureCreated();

    for (final String id in <String>[
      kBookA1,
      kBookA2,
      kBookA3,
      kBookB1,
      kBookC1,
    ]) {
      await File(
        '${paths.pdfDirectory.path}${Platform.pathSeparator}$id.pdf',
      ).writeAsString('pdf');
    }

    library = LibraryProvider(
      paths: paths,
      store: MemoryStore(),
      logger: AppLogger(verbose: false),
    );
    await library.load(index: buildCatalogIndex());
  });

  tearDown(() async {
    library.dispose();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  /// 分区摘要，形如 `语文: 语文一年级上册/语文一年级下册 | 数学: ...`。
  ///
  /// 断言整条分区链（有哪几区、顺序、每区有谁）比逐条断言更能说明"书被归到一起了"。
  /// 书名去掉重复的前缀，否则一行断言读起来全是噪声。
  String shape() => library.sections
      .map((LibrarySection section) {
        final String label = switch (section.kind) {
          LibrarySectionKind.pinned => '置顶',
          LibrarySectionKind.group => section.title!,
          LibrarySectionKind.ungrouped => '未分组',
        };
        final String titles = section.books
            .map((LibraryBook book) => book.title.replaceFirst(_titlePrefix, ''))
            .join('/');
        return '$label: $titles';
      })
      .join(' | ');

  test('没有分组时是一整块，不分区', () async {
    expect(library.sections, hasLength(1));
    expect(library.sections.single.kind, LibrarySectionKind.ungrouped);
    expect(library.sections.single.books, hasLength(5));
  });

  test('同一组的书归到一起，不再散在按书名排的长队里', () async {
    await library.assignGroup(<String>{kBookA1, kBookA3}, '语文');
    await library.assignGroup(<String>{kBookB1}, '数学');

    // 语文区里是 a1 与 a3——它们本来夹在 a2、b1、c1 之间。
    expect(
      shape(),
      '语文: 语文一年级上册/语文一年级下册'
      ' | 数学: 数学一年级上册'
      ' | 未分组: 语文一年级上册（大字版）/语文七年级上册',
    );
  });

  test('分组之间按创建顺序，不按名称', () async {
    // 「数学」先建，就该排在「语文」前面——按码位排的话结果正好相反。
    await library.assignGroup(<String>{kBookB1}, '数学');
    await library.assignGroup(<String>{kBookA1}, '语文');

    expect(library.groupNames, <String>['数学', '语文']);
    expect(library.sections.first.title, '数学');
  });

  test('未分组永远排在最后', () async {
    await library.assignGroup(<String>{kBookC1}, '七年级');

    expect(library.sections.last.kind, LibrarySectionKind.ungrouped);
  });

  test('置顶独立成区，并从所属分组里移出', () async {
    await library.assignGroup(<String>{kBookA1, kBookA3}, '语文');
    await library.togglePin(<String>{kBookA1});

    expect(library.sections.first.kind, LibrarySectionKind.pinned);
    expect(library.sections.first.books.single.id, kBookA1);
    // 语文区里只剩 a3：同一本书不会既在置顶区又在分组里。
    expect(library.sections[1].title, '语文');
    expect(
      library.sections[1].books.map((LibraryBook b) => b.id),
      <String>[kBookA3],
    );
    // 但归属仍然记着，封面上的分组角标照常。
    expect(library.groupOf(kBookA1), '语文');
  });

  test('取消置顶后回到原来的分组', () async {
    await library.assignGroup(<String>{kBookA1, kBookA3}, '语文');
    await library.togglePin(<String>{kBookA1});
    await library.togglePin(<String>{kBookA1});

    expect(library.sections, hasLength(2));
    expect(library.sections.first.title, '语文');
    expect(library.sections.first.books, hasLength(2));
  });

  test('空掉的分组不再占位置', () async {
    await library.assignGroup(<String>{kBookA1}, '旧分组');
    await library.assignGroup(<String>{kBookA1}, '新分组');

    expect(library.groupNames, <String>['新分组']);
  });

  test('把书重新归回已存在的分组，不会把它挪到顺序表末尾', () async {
    await library.assignGroup(<String>{kBookA1}, '语文');
    await library.assignGroup(<String>{kBookB1}, '数学');
    await library.assignGroup(<String>{kBookA1}, '数学');
    // 语文已经没书了，会被裁掉；数学保持原位。
    expect(library.groupNames, <String>['数学']);

    await library.assignGroup(<String>{kBookA1}, '语文');
    expect(library.groupNames, <String>['数学', '语文']);
  });

  test('移出书架会一并清掉分组，并裁掉空分组', () async {
    await library.assignGroup(<String>{kBookA1}, '语文');
    await library.removeMany(<String>{kBookA1});

    expect(library.groupNames, isEmpty);
    expect(library.sections.single.kind, LibrarySectionKind.ungrouped);
  });

  test('顺序表写进了存储，重新加载后仍然按创建顺序', () async {
    final MemoryStore store = MemoryStore();
    final LibraryProvider first = LibraryProvider(
      paths: paths,
      store: store,
      logger: AppLogger(verbose: false),
    );
    await first.load(index: buildCatalogIndex());
    await first.assignGroup(<String>{kBookB1}, '数学');
    await first.assignGroup(<String>{kBookA1}, '语文');
    first.dispose();

    final LibraryProvider second = LibraryProvider(
      paths: paths,
      store: store,
      logger: AppLogger(verbose: false),
    );
    await second.load(index: buildCatalogIndex());
    expect(second.groupNames, <String>['数学', '语文']);
    second.dispose();
  });

  group('整理信息的兼容性', () {
    test('没有 groupOrder 的老数据：分组照常读出来', () {
      // 老版本只写了 pinned 与 groups，没有顺序表。
      final LibraryArrangement legacy = LibraryArrangement.fromJson(
        jsonDecode('{"pinned":[],"groups":{"a1":"语文"}}')
            as Map<String, dynamic>,
      );

      expect(legacy.groupNames, <String>['语文']);
    });

    test('顺序表里有已不存在的分组名：忽略它，不报错', () {
      final LibraryArrangement arrangement = LibraryArrangement.fromJson(
        jsonDecode(
              '{"pinned":[],"groups":{"a1":"语文"},"groupOrder":["数学","语文"]}',
            )
            as Map<String, dynamic>,
      );

      expect(arrangement.groupNames, <String>['语文']);
    });

    test('顺序表与分组对不上：漏掉的名字排到最后，不丢分组', () {
      final LibraryArrangement arrangement = LibraryArrangement.fromJson(
        jsonDecode(
              '{"pinned":[],"groups":{"a1":"语文","b1":"数学"},'
              '"groupOrder":["数学"]}',
            )
            as Map<String, dynamic>,
      );

      expect(arrangement.groupNames, <String>['数学', '语文']);
    });
  });
}
