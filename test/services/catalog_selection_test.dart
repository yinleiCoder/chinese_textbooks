import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/services/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_fixture.dart';

/// 三态勾选的行为约定。
///
/// 这层是"看起来简单、写起来容易崩"的典型：状态是派生的，一旦派生逻辑
/// 在某条路径上漏算，界面上就会出现"父节点明明该是半选却显示未选"这类
/// 隐蔽 bug。所以每个变更路径都要有断言。
void main() {
  late CatalogIndex index;
  late CatalogSelection selection;

  setUp(() {
    index = buildCatalogIndex();
    selection = CatalogSelection(index: index);
  });

  /// 上册节点的子树规模：A1 + A2。
  const String volume1 = kNodePrimaryChineseGrade1Volume1;

  /// 一年级：A1 + A2 + A3。
  const String grade1 = kNodeGrade1;

  /// 语文：A1 + A2 + A3。
  const String chinese = kNodeChinese;

  group('初始状态', () {
    test('什么都没选', () {
      expect(selection.isEmpty, isTrue);
      expect(selection.selectedCount, 0);
      expect(selection.stateOf(volume1), SelectionState.none);
      expect(selection.selectedCountOf(kNodePrimary), 0);
    });
  });

  group('勾选单本', () {
    test('只重算到根这条链上的节点', () {
      selection.setBook(kBookA1, selected: true);

      expect(selection.isSelected(kBookA1), isTrue);
      expect(selection.selectedCount, 1);

      // 上册：2 本里选了 1 本 → 半选
      expect(selection.stateOf(volume1), SelectionState.partial);
      expect(selection.selectedCountOf(volume1), 1);

      // 一年级：3 本里 1 本 → 半选
      expect(selection.stateOf(grade1), SelectionState.partial);
      expect(selection.selectedCountOf(grade1), 1);

      // 小学：4 本里 1 本 → 半选
      expect(selection.stateOf(kNodePrimary), SelectionState.partial);
      expect(selection.selectedCountOf(kNodePrimary), 1);
    });

    test('子树全选后状态变成 all', () {
      selection
        ..setBook(kBookA1, selected: true)
        ..setBook(kBookA2, selected: true);

      expect(selection.stateOf(volume1), SelectionState.all);
      expect(selection.selectedCountOf(volume1), 2);
      // 一年级的第三本还没选，仍是半选。
      expect(selection.stateOf(grade1), SelectionState.partial);
    });

    test('取消后状态回退', () {
      selection
        ..setBook(kBookA1, selected: true)
        ..setBook(kBookA2, selected: true)
        ..setBook(kBookA1, selected: false);

      expect(selection.stateOf(volume1), SelectionState.partial);
      expect(selection.selectedCountOf(volume1), 1);
      expect(selection.isSelected(kBookA1), isFalse);
    });

    test('重复设置同一状态不产生变化', () {
      selection.setBook(kBookA1, selected: false);
      expect(selection.selectedCount, 0);
    });
  });

  group('勾选整个分类', () {
    test('一次选中整棵子树', () {
      selection.setNode(grade1, selected: true);

      expect(selection.selectedCount, 3);
      expect(selection.stateOf(grade1), SelectionState.all);
      expect(selection.stateOf(chinese), SelectionState.all);
      // 小学还有数学那一本，所以只是半选。
      expect(selection.stateOf(kNodePrimary), SelectionState.partial);
      expect(selection.selectedCountOf(kNodePrimary), 3);
    });

    test('一次取消整棵子树', () {
      selection
        ..setNode(kNodePrimary, selected: true)
        ..setNode(grade1, selected: false);

      expect(selection.selectedCount, 1);
      expect(selection.stateOf(grade1), SelectionState.none);
      expect(selection.stateOf(kNodePrimary), SelectionState.partial);
    });

    test('全选根节点后整棵树都是 all', () {
      for (final node in index.roots) {
        selection.setNode(node.id, selected: true);
      }
      expect(selection.selectedCount, 5);
      expect(selection.stateOf(kNodePrimary), SelectionState.all);
    });
  });

  group('批量操作', () {
    test('addAll 只增不减', () {
      selection
        ..setBook(kBookA1, selected: true)
        ..addAll(<String>[kBookB1]);

      expect(selection.selectedCount, 2);
      expect(selection.stateOf(kNodePrimary), SelectionState.partial);
      expect(selection.selectedCountOf(kNodePrimary), 2);
    });

    test('一次选满整个子树后父节点变成 all', () {
      selection.addAll(<String>[kBookA1, kBookA2, kBookA3, kBookB1]);
      expect(selection.stateOf(kNodePrimary), SelectionState.all);
    });

    test('removeAll 批量取消', () {
      selection
        ..addAll(<String>[kBookA1, kBookA2])
        ..removeAll(<String>[kBookA1, kBookA2]);

      expect(selection.isEmpty, isTrue);
      expect(selection.stateOf(volume1), SelectionState.none);
    });

    test('clear 清空全部', () {
      selection
        ..addAll(<String>[kBookA1, kBookC1])
        ..clear();

      expect(selection.isEmpty, isTrue);
      expect(selection.stateOf(kNodePrimary), SelectionState.none);
    });
  });

  group('反选', () {
    test('未全选时全选', () {
      selection.toggleAll(<String>[kBookA1, kBookA2]);
      expect(selection.selectedCount, 2);
    });

    test('已全选时取消', () {
      selection
        ..addAll(<String>[kBookA1, kBookA2])
        ..toggleAll(<String>[kBookA1, kBookA2]);

      expect(selection.isEmpty, isTrue);
    });

    test('只选了一部分时是全选，不是取消', () {
      selection
        ..setBook(kBookA1, selected: true)
        ..toggleAll(<String>[kBookA1, kBookA2]);

      expect(selection.selectedCount, 2);
      expect(selection.isSelected(kBookA2), isTrue);
    });
  });

  group('选择集与筛选解耦', () {
    test('按筛选结果批量勾选后，条件收紧也不影响已选', () {
      // 先按"小学"筛出 4 本并全选。
      final List<Textbook> primaryOnly = index.filterAndSearch(
        const CatalogFilter().toggle('zxxxd', kNodePrimary),
        '',
      );
      selection.addAll(primaryOnly.map((Textbook book) => book.id));
      expect(selection.selectedCount, 4);

      // 换成只看"初中"，选择集不受影响——它只认教材 id，不认识筛选条件。
      final List<Textbook> juniorOnly = index.filterAndSearch(
        const CatalogFilter().toggle('zxxxd', kNodeJunior),
        '',
      );
      expect(juniorOnly, hasLength(1));
      expect(selection.selectedCount, 4);
      expect(selection.stateOf(kNodePrimary), SelectionState.all);
      expect(selection.stateOf(kNodeJunior), SelectionState.none);
    });
  });
}
