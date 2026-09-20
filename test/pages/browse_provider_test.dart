import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/pages/browse/browse_provider.dart';
import 'package:chinese_textbooks/pages/browse/browse_row.dart';
import 'package:chinese_textbooks/services/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/catalog_fixture.dart';

void main() {
  late CatalogIndex index;
  late BrowseProvider browse;

  setUp(() {
    index = buildCatalogIndex();
    browse = BrowseProvider(index: index);
  });

  tearDown(() => browse.dispose());

  group('初始状态', () {
    test('默认是树模式，只展示折叠的根节点', () {
      expect(browse.mode, BrowseMode.tree);
      expect(browse.rows, hasLength(2)); // 小学 / 初中
      expect(browse.rows.every((BrowseRow row) => row is BrowseNodeRow), isTrue);
      expect(browse.hasExpanded, isFalse);
    });

    test('没有勾选', () {
      expect(browse.selection.isEmpty, isTrue);
      expect(browse.selectedBooks, isEmpty);
    });
  });

  group('树的展开', () {
    test('展开一层，子节点出现在行里', () {
      browse.toggleExpanded(kNodePrimary);

      final List<String> labels = browse.rows
          .whereType<BrowseNodeRow>()
          .map((BrowseNodeRow row) => row.node.label)
          .toList();
      expect(labels, <String>['小学', '语文', '数学', '初中']);
      expect(browse.hasExpanded, isTrue);
    });

    test('展开到有教材的节点，教材作为叶子内联出现', () {
      browse
        ..toggleExpanded(kNodePrimary)
        ..toggleExpanded(kNodeChinese)
        ..toggleExpanded('$kNodeChinese/t-tbb')
        ..toggleExpanded(kNodeGrade1)
        ..toggleExpanded(kNodePrimaryChineseGrade1Volume1);

      final Iterable<BrowseBookRow> books = browse.rows.whereType<BrowseBookRow>();
      expect(books.map((BrowseBookRow row) => row.book.id), <String>[
        kBookA1,
        kBookA2,
      ]);
    });

    test('再次点击收起', () {
      browse
        ..toggleExpanded(kNodePrimary)
        ..toggleExpanded(kNodePrimary);
      expect(browse.rows, hasLength(2));
      expect(browse.hasExpanded, isFalse);
    });

    test('展开全部后所有教材都可见', () {
      browse.expandAll();
      final int bookRows = browse.rows.whereType<BrowseBookRow>().length;
      expect(bookRows, index.length);
    });

    test('收起全部回到初始行数', () {
      browse
        ..expandAll()
        ..collapseAll();
      expect(browse.rows, hasLength(2));
    });
  });

  group('模式切换', () {
    test('一旦有关键词就切成扁平列表', () {
      browse.setQuery('语文');
      expect(browse.mode, BrowseMode.list);
      // 小学的语文 3 本 + 初中的语文 1 本，共 4 本。
      expect(browse.results.map((Textbook b) => b.id), <String>[
        kBookA1,
        kBookA2,
        kBookA3,
        kBookC1,
      ]);
    });

    test('一旦有筛选条件也切成扁平列表', () {
      browse.toggleFilter('zxxxd', kNodePrimary);
      expect(browse.mode, BrowseMode.list);
      expect(browse.results, hasLength(4));
    });

    test('清空条件后回到树模式', () {
      browse
        ..setQuery('语文')
        ..toggleFilter('zxxxd', kNodePrimary)
        ..clearAllFilters();

      expect(browse.mode, BrowseMode.tree);
      expect(browse.filter.isEmpty, isTrue);
      expect(browse.query, isEmpty);
    });

    test('结果为空时返回空列表而不是报错', () {
      browse.setQuery('不存在的学科');
      expect(browse.results, isEmpty);
    });
  });

  group('勾选', () {
    test('勾选单本', () {
      browse.setBookSelected(kBookA1, selected: true);
      expect(browse.selection.isSelected(kBookA1), isTrue);
      expect(browse.selectedBooks.map((Textbook b) => b.id), <String>[kBookA1]);
    });

    test('全选某个分类', () {
      browse.setNodeSelected(kNodePrimary, selected: true);
      expect(browse.selection.selectedCount, 4);
      expect(browse.selection.stateOf(kNodePrimary), SelectionState.all);
    });

    test('selectedBooks 按索引顺序返回，而不是勾选顺序', () {
      // 先勾后面的，再勾前面的。
      browse
        ..setBookSelected(kBookC1, selected: true)
        ..setBookSelected(kBookA1, selected: true);

      expect(browse.selectedBooks.map((Textbook b) => b.id), <String>[
        kBookA1,
        kBookC1,
      ]);
    });

    test('全选当前可见结果', () {
      browse
        ..setQuery('语文')
        ..toggleAllVisible();
      expect(browse.selection.selectedCount, 4);
    });

    test('再点一次全选结果变成取消', () {
      browse
        ..setQuery('语文')
        ..toggleAllVisible()
        ..toggleAllVisible();
      expect(browse.selection.isEmpty, isTrue);
    });

    test('清空勾选', () {
      browse
        ..setNodeSelected(kNodePrimary, selected: true)
        ..clearSelection();
      expect(browse.selection.isEmpty, isTrue);
    });
  });

  group('勾选与筛选互不影响', () {
    test('切换筛选条件不会丢掉已勾选的书', () {
      // 先在"小学"下勾两本。
      browse
        ..toggleFilter('zxxxd', kNodePrimary)
        ..setQuery('语文')
        ..setBookSelected(kBookA1, selected: true)
        // 换成完全不相干的条件。
        ..clearAllFilters()
        ..toggleFilter('zxxxd', kNodeJunior);

      expect(browse.selection.selectedCount, 1);
      expect(browse.selection.isSelected(kBookA1), isTrue);
      // 当前结果里没有它，所以"全选结果"不该把它算进去。
      expect(browse.results.map((Textbook b) => b.id), <String>[kBookC1]);
    });

    test('不同筛选条件下分几次勾选，最后一起下载', () {
      browse
        ..toggleFilter('zxxxd', kNodePrimary)
        ..setQuery('语文')
        ..toggleAllVisible()
        ..clearAllFilters()
        ..toggleFilter('zxxxd', kNodeJunior)
        ..toggleAllVisible();

      expect(browse.selection.selectedCount, 4);
      expect(browse.selectedBooks.map((Textbook b) => b.id), <String>[
        kBookA1,
        kBookA2,
        kBookA3,
        kBookC1,
      ]);
    });
  });

  group('行缓存', () {
    test('重复读取 rows 返回同一份，展开后才重算', () {
      final List<BrowseRow> first = browse.rows;
      expect(identical(browse.rows, first), isTrue);

      browse.toggleExpanded(kNodePrimary);
      expect(identical(browse.rows, first), isFalse);
    });

    test('重复读取 results 复用缓存，改条件后重算', () {
      browse.setQuery('语文');
      final List<Textbook> first = browse.results;
      expect(identical(browse.results, first), isTrue);

      browse.setQuery('数学');
      expect(identical(browse.results, first), isFalse);
    });
  });
}
