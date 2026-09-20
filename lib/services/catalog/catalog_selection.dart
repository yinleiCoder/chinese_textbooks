import '../../entity/entity.dart';
import 'catalog_index.dart';

/// 一个分类节点相对当前选择集的三态。
enum SelectionState {
  /// 子树内一本都没选。
  none,

  /// 选了一部分。
  partial,

  /// 子树内全部选中。
  all,
}

/// 目录树的勾选状态。
///
/// ## 只存叶子
///
/// 状态的唯一真相是 `Set<String> _selected`（教材 id）。节点态是**派生**的。
/// 这样做的三个理由：
/// 1. 教材行、详情页、下载前都要问"这本选了吗"，集合查询是 O(1)；
/// 2. 搜索或筛选把某本书藏起来时，它的勾选**自动保留**，不需要任何补偿逻辑；
/// 3. 全选某个分类退化成一次 `addAll`，不必遍历子树逐个标记。
///
/// ## 祖先态不递归全树
///
/// 勾选一本教材时，只有它到根这条链会变。所以 [_recomputeUpward] 只重算
/// 这条链（约 6 层 × 8 个分支 ≈ 50 次操作），用户连点也不会掉帧。
///
/// 批量操作（全选筛选结果、全选某个分类）走另一条路：清空缓存后按**层号从深到浅**
/// 整体重算一次，O(节点数) ≈ 4000 次。
///
/// ## 为什么缓存的是"状态 + 已选数"而不是光状态
///
/// 半选节点的子树里究竟选了几本，从 [SelectionState.partial] 这一个枚举值
/// 推不出来。只缓存枚举的话，父节点为了算自己的精确计数就不得不递归下去——
/// 恰好是这套设计要避免的事。
final class CatalogSelection {
  CatalogSelection({required CatalogIndex index}) : _index = index {
    // 深度从大到小：重算时子节点一定先于父节点算完。
    _nodesByDepthDesc = List<String>.of(index.nodeById.keys)
      ..sort(
        (String a, String b) =>
            index.nodeById[b]!.depth.compareTo(index.nodeById[a]!.depth),
      );
  }

  final CatalogIndex _index;
  final Set<String> _selected = <String>{};
  final Map<String, _NodeStat> _stats = <String, _NodeStat>{};
  late final List<String> _nodesByDepthDesc;

  /// 已选教材数量。
  int get selectedCount => _selected.length;

  /// 是否一件都没选。
  bool get isEmpty => _selected.isEmpty;

  /// 已选教材 id 的只读视图。
  Set<String> get selectedBookIds => Set<String>.unmodifiable(_selected);

  /// 某本教材是否被勾选。
  bool isSelected(String bookId) => _selected.contains(bookId);

  /// 某个分类节点的三态。
  SelectionState stateOf(String nodeId) =>
      _stats[nodeId]?.state ?? SelectionState.none;

  /// 某个分类节点子树内的已选数量。
  int selectedCountOf(String nodeId) => _stats[nodeId]?.selectedCount ?? 0;

  /// 勾选 / 取消单本教材。
  void setBook(String bookId, {required bool selected}) {
    if (selected == isSelected(bookId)) {
      return;
    }
    if (selected) {
      _selected.add(bookId);
    } else {
      _selected.remove(bookId);
    }
    _recomputeUpward(bookId);
  }

  /// 全选 / 全不选某个分类的整棵子树。
  void setNode(String nodeId, {required bool selected}) {
    final CatalogNode? node = _index.nodeById[nodeId];
    if (node == null) {
      return;
    }
    final Set<String> ids = node.descendantBookIds.toSet();
    if (selected) {
      _selected.addAll(ids);
    } else {
      _selected.removeAll(ids);
    }
    _recomputeAll();
  }

  /// 批量加入选择集。
  ///
  /// 用于"全选当前筛选结果"。**只增不减**：用户在不同筛选条件下分几次勾选，
  /// 切回宽松条件时先前选的应当还在。
  void addAll(Iterable<String> bookIds) {
    final int before = _selected.length;
    _selected.addAll(bookIds);
    if (_selected.length != before) {
      _recomputeAll();
    }
  }

  /// 批量移出选择集。
  void removeAll(Iterable<String> bookIds) {
    final int before = _selected.length;
    _selected.removeAll(bookIds);
    if (_selected.length != before) {
      _recomputeAll();
    }
  }

  /// 清空全部选择。
  void clear() {
    if (_selected.isEmpty) {
      return;
    }
    _selected.clear();
    _recomputeAll();
  }

  /// 按当前选择集反选给定的教材集合。
  ///
  /// 语义是"如果它们已经全选了就取消，否则全选"，
  /// 用于结果列表上的"全选 / 取消全选"按钮。
  void toggleAll(Iterable<String> bookIds) {
    final List<String> ids = bookIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final bool allSelected = ids.every(_selected.contains);
    if (allSelected) {
      removeAll(ids);
    } else {
      addAll(ids);
    }
  }

  /// 从教材 id 链重算到根。
  void _recomputeUpward(String bookId) {
    String? nodeId = _index.leafOwnerNodeId[bookId];
    while (nodeId != null) {
      _stats[nodeId] = _derive(nodeId);
      nodeId = _index.nodeById[nodeId]?.parentId;
    }
  }

  /// 整体重算。仅在批量操作后使用。
  void _recomputeAll() {
    _stats.clear();
    for (final String nodeId in _nodesByDepthDesc) {
      _stats[nodeId] = _derive(nodeId);
    }
  }

  /// 由直接子节点与直接教材推导本节点状态。
  ///
  /// 调用前提：所有子节点的 [_stats] 已是最新。
  _NodeStat _derive(String nodeId) {
    final CatalogNode? node = _index.nodeById[nodeId];
    if (node == null) {
      return (state: SelectionState.none, selectedCount: 0);
    }

    int selected = 0;
    for (final Textbook book in node.books) {
      if (_selected.contains(book.id)) {
        selected++;
      }
    }
    for (final CatalogNode child in node.children) {
      selected += _stats[child.id]?.selectedCount ?? 0;
    }

    final int total = node.descendantBookCount;
    final SelectionState state;
    if (selected == 0) {
      state = SelectionState.none;
    } else if (selected >= total) {
      state = SelectionState.all;
    } else {
      state = SelectionState.partial;
    }
    return (state: state, selectedCount: selected);
  }
}

/// 节点的三态与已选数。
///
/// 用记录类型而不是类：它是纯数据、生命周期极短，
/// 每次重算都会新建，用类反而增加分配与样板。
typedef _NodeStat = ({SelectionState state, int selectedCount});
