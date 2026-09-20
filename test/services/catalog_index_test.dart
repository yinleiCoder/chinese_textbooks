import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/services/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_fixture.dart';

void main() {
  late CatalogIndex index;

  setUp(() => index = buildCatalogIndex());

  group('建树', () {
    test('没有教材的分支被剪掉', () {
      // 「教材」(t-jc) 下没有任何书，不该出现在结果里。
      expect(index.nodeById.containsKey('t-jc'), isFalse);
      expect(index.nodeById.containsKey('t-dzjc'), isFalse);
    });

    test('唯一的顶层节点被上提，目录页直接展示学段', () {
      // 「电子教材」是唯一顶层节点，被上提后不占一层。
      expect(
        index.roots.map((CatalogNode node) => node.label),
        <String>['小学', '初中'],
      );
    });

    test('节点 id 是从可见根算起的路径', () {
      final CatalogNode volume1 =
          index.nodeById[kNodePrimaryChineseGrade1Volume1]!;
      expect(volume1.label, '上册');
      expect(volume1.tagId, 't-sc');
      expect(volume1.depth, 4);
      expect(volume1.parentId, kNodeGrade1);
    });

    test('教材挂到路径最深的那个节点', () {
      expect(index.leafOwnerNodeId[kBookA1], kNodePrimaryChineseGrade1Volume1);
      expect(index.leafOwnerNodeId[kBookB1], kNodeMathGrade1Volume1);
      expect(index.leafOwnerNodeId[kBookC1], kNodeJuniorChineseGrade7Volume1);
    });

    test('tag_paths 为空或路径走不到节点的条目被跳过', () {
      expect(index.byId('book-empty-path'), isNull);
      expect(index.byId('book-short-path'), isNull);
      expect(index.length, 5);
    });

    test('子树教材数量在建树时算好', () {
      // 小学下有 语文(A1,A2,A3) + 数学(B1) 共 4 本。
      expect(index.nodeById[kNodePrimary]!.descendantBookCount, 4);
      expect(
        index.nodeById[kNodePrimaryChineseGrade1Volume1]!.descendantBookCount,
        2,
      );
    });
  });

  group('筛选维度', () {
    test('按维度组织，顺序是教学顺序而不是层号', () {
      expect(
        index.facets.map((CatalogFacet facet) => facet.label),
        <String>['学段', '学科', '版本', '年级', '册次'],
      );
      expect(index.facets.first.dimensionId, 'zxxxd');
    });

    test('候选项按教材数量降序', () {
      final CatalogFacet stage = index.facets.first;
      expect(stage.options.first.tagId, 't-xx');
      expect(stage.options.first.label, '小学');
      expect(stage.options.first.bookCount, 4);
    });

    test('同一 tag 在树里出现多次时，计数会合并', () {
      // 夹具里 t-1nj（一年级）只出现一次，这里验的是合并逻辑本身：
      // 每个 tag 的计数等于"分类链里含它的教材数"。
      final CatalogFacet grade = index.facets.firstWhere(
        (CatalogFacet facet) => facet.dimensionId == 'zxxnj',
      );
      final CatalogLevelOption option = grade.options.firstWhere(
        (CatalogLevelOption o) => o.tagId == 't-1nj',
      );
      expect(option.bookCount, 3);
    });
  });

  group('筛选', () {
    test('不设条件时返回全部', () {
      expect(index.filterAndSearch(const CatalogFilter(), ''), hasLength(5));
    });

    test('按学段筛选', () {
      final List<Textbook> result = index.filterAndSearch(
        const CatalogFilter().toggle('zxxxd', 't-xx'),
        '',
      );
      expect(result.map((Textbook b) => b.id), <String>[
        kBookA1,
        kBookA2,
        kBookA3,
        kBookB1,
      ]);
    });

    test('跨维度是「且」的关系', () {
      final List<Textbook> result = index.filterAndSearch(
        const CatalogFilter().toggle('zxxxd', 't-xx').toggle('zxxxk', 't-sx'),
        '',
      );
      expect(result.map((Textbook b) => b.id), <String>[kBookB1]);
    });

    test('同一维度内是「或」的关系', () {
      // 小学的语文(t-yw) 3 本 + 数学(t-sx) 1 本。
      // 注意初中的语文是**另一个 tag_id**(t-yw2)——同名分类在不同父节点下
      // 是不同的 tag，这正是筛选要按 tag_id 而不是按名称匹配的原因。
      final List<Textbook> result = index.filterAndSearch(
        const CatalogFilter().toggle('zxxxk', 't-yw').toggle('zxxxk', 't-sx'),
        '',
      );
      expect(result.map((Textbook b) => b.id), <String>[
        kBookA1,
        kBookA2,
        kBookA3,
        kBookB1,
      ]);
    });

    test('按维度匹配而不是按层号，深度不一致也能命中', () {
      // 「版本」在不同分支上的深度并不相同，按层号对齐会漏。
      final List<Textbook> result = index.filterAndSearch(
        const CatalogFilter().toggle('zxxbb', 't-rjb'),
        '',
      );
      expect(result.map((Textbook b) => b.id), <String>[kBookB1]);
    });

    test('清空条件恢复全部', () {
      final CatalogFilter filter = const CatalogFilter()
          .toggle('zxxxd', 't-xx')
          .cleared();
      expect(index.filterAndSearch(filter, ''), hasLength(5));
    });
  });

  group('搜索', () {
    test('分词后要求每个词都命中（AND 语义）', () {
      final List<Textbook> result = index.filterAndSearch(
        const CatalogFilter(),
        '语文 一年级',
      );
      expect(result.map((Textbook b) => b.id), <String>[
        kBookA1,
        kBookA2,
        kBookA3,
      ]);
    });

    test('能按分类路径里的版本名搜到', () {
      // 「人教版」出现在路径的版本层，不在书名里。
      final List<Textbook> result = index.filterAndSearch(
        const CatalogFilter(),
        '人教版',
      );
      expect(result.map((Textbook b) => b.id), <String>[kBookB1]);
    });

    test('搜索与筛选叠加', () {
      final List<Textbook> result = index.filterAndSearch(
        const CatalogFilter().toggle('zxxxd', 't-cz'),
        '语文',
      );
      expect(result.map((Textbook b) => b.id), <String>[kBookC1]);
    });

    test('命中的关键词为空时等同不搜索', () {
      expect(index.filterAndSearch(const CatalogFilter(), '   '), hasLength(5));
    });

    test('搜不到时返回空列表', () {
      expect(index.filterAndSearch(const CatalogFilter(), '不存在的学科'), isEmpty);
    });
  });

  group('查询', () {
    test('byId 取回教材', () {
      expect(index.byId(kBookA1)?.title, contains('语文一年级上册'));
      expect(index.byId('不存在'), isNull);
    });

    test('分类路径拼接成可读文本', () {
      expect(
        index.categoryPathOf(index.byId(kBookA1)!),
        '小学 › 语文 › 统编版 › 一年级 › 上册',
      );
    });
  });

  group('空数据', () {
    test('没有任何条目时索引仍可用', () {
      final CatalogIndex empty = CatalogIndex.build(
        rows: const <List<String>>[],
        tagTreeJson: const <String, dynamic>{'hierarchies': <dynamic>[]},
      );
      expect(empty.isEmpty, isTrue);
      expect(empty.roots, isEmpty);
      expect(empty.facets, isEmpty);
      expect(empty.filterAndSearch(const CatalogFilter(), '语文'), isEmpty);
    });
  });

  group('分片编解码', () {
    test('编解码往返一致', () {
      const List<List<String>> rows = <List<String>>[
        <String>[
          'id-1',
          '书名',
          'a/b/c',
          '出版社',
          'https://x/y.jpg',
          '2026-01-02T03:04:05.000+0800',
        ],
      ];
      final List<List<String>>? decoded = CatalogShardCodec.decode(
        CatalogShardCodec.encode(rows),
      );
      expect(decoded, rows);
    });

    test('行残缺时整体作废，而不是产出半截数据', () {
      expect(CatalogShardCodec.decode('{"v":1,"rows":[["只有一列"]]}'), isNull);
    });

    test('格式版本不符时作废', () {
      expect(CatalogShardCodec.decode('{"v":999,"rows":[]}'), isNull);
    });

    test('非法 JSON 返回 null 而不是抛异常', () {
      expect(CatalogShardCodec.decode('不是 JSON'), isNull);
    });

    test('空字符串字段还原成 null', () {
      final Textbook book = CatalogShardCodec.toTextbook(
        <String>['id-1', '书名', 'a/b', '', '', ''],
      );
      expect(book.providerName, isNull);
      expect(book.previewUrl, isNull);
      expect(book.updateTime, isNull);
      expect(book.tagPath, <String>['a', 'b']);
    });
  });
}
