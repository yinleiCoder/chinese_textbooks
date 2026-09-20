import 'package:flutter/foundation.dart';

import '../../entity/entity.dart';
import '../../services/catalog/catalog.dart';
import 'browse_row.dart';

/// 目录页的浏览模式。
enum BrowseMode {
  /// 分类树。
  tree,

  /// 扁平结果列表。
  ///
  /// 一旦有筛选条件或搜索关键词就切到它：树在结果稀疏时会退化成一堆
  /// 只有一个孩子的节点，逐层点进去找书远不如直接列出来。
  list,
}

/// 目录页的页面私有状态。
///
/// 按项目约定，只有跨页面共享的状态才放进 `providers/`。
/// 筛选条件、展开状态、勾选集合都是**只在目录页有意义**的东西，
/// 下载页并不关心用户勾了什么，因此它们留在这里。
///
/// 状态的生命周期与 `BrowsePage` 绑定：`StatefulShellRoute.indexedStack`
/// 会让切走的 Tab 保持存活，所以切到下载页再切回来，展开与勾选都还在。
final class BrowseProvider extends ChangeNotifier {
  BrowseProvider({required CatalogIndex index}) : _index = index {
    _selection = CatalogSelection(index: index);
  }

  final CatalogIndex _index;
  late final CatalogSelection _selection;

  /// 已展开的节点 id。
  final Set<String> _expanded = <String>{};

  CatalogFilter _filter = const CatalogFilter();
  String _query = '';

  // 展开状态或筛选条件变化时才重算，避免每帧都重建几千行。
  List<BrowseRow>? _cachedRows;
  List<Textbook>? _cachedResults;

  /// 目录索引。
  CatalogIndex get index => _index;

  /// 勾选状态。
  CatalogSelection get selection => _selection;

  /// 当前筛选条件。
  CatalogFilter get filter => _filter;

  /// 当前搜索词。
  String get query => _query;

  /// 是否处于筛选 / 搜索状态。
  bool get isFiltering => !_filter.isEmpty || _query.trim().isNotEmpty;

  /// 当前模式。
  BrowseMode get mode => isFiltering ? BrowseMode.list : BrowseMode.tree;

  /// 扁平结果列表（仅在 [BrowseMode.list] 下有意义）。
  List<Textbook> get results =>
      _cachedResults ??= _index.filterAndSearch(_filter, _query);

  /// 树模式下展平后的可见行。
  List<BrowseRow> get rows => _cachedRows ??= _buildRows();

  /// 当前模式下可供"全选"的教材。
  ///
  /// 语义是"把当前看得见的都选上"，因此以筛选/搜索结果为准。
  List<Textbook> get visibleBooks => isFiltering ? results : _index.items;

  // ==================== 展开 ====================

  /// 某个节点是否已展开。
  bool isExpanded(String nodeId) => _expanded.contains(nodeId);

  /// 是否有任何节点处于展开状态。
  ///
  /// 用于把"展开全部 / 收起全部"合成一个按钮：树全收起时它的语义是展开，
  /// 否则是收起。这比放两个按钮省地方，也符合用户的心理模型。
  bool get hasExpanded => _expanded.isNotEmpty;

  /// 展开 / 收起某个节点。
  void toggleExpanded(String nodeId) {
    if (!_expanded.remove(nodeId)) {
      _expanded.add(nodeId);
    }
    _invalidateRows();
    notifyListeners();
  }

  /// 展开全部节点。
  ///
  /// 只在树的规模可控时提供——本树约 200 个分类节点，
  /// 展开全部会让列表多出几千行，但 `ListView.builder` 只构建视口内的部分，
  /// 代价可以接受。
  void expandAll() {
    for (final CatalogNode node in _index.nodeById.values) {
      if (node.hasChildren || node.hasBooks) {
        _expanded.add(node.id);
      }
    }
    _invalidateRows();
    notifyListeners();
  }

  /// 收起全部。
  void collapseAll() {
    if (_expanded.isEmpty) {
      return;
    }
    _expanded.clear();
    _invalidateRows();
    notifyListeners();
  }

  // ==================== 筛选与搜索 ====================

  /// 设置搜索词。
  void setQuery(String value) {
    if (value == _query) {
      return;
    }
    _query = value;
    _invalidateAll();
    notifyListeners();
  }

  /// 切换某个筛选维度下的一个选项。
  void toggleFilter(String dimensionId, String tagId) {
    _filter = _filter.toggle(dimensionId, tagId);
    _invalidateAll();
    notifyListeners();
  }

  /// 清空某个维度。
  void clearDimension(String dimensionId) {
    _filter = _filter.clearDimension(dimensionId);
    _invalidateAll();
    notifyListeners();
  }

  /// 清空全部筛选与搜索词。
  void clearAllFilters() {
    if (_filter.isEmpty && _query.isEmpty) {
      return;
    }
    _filter = const CatalogFilter();
    _query = '';
    _invalidateAll();
    notifyListeners();
  }

  // ==================== 勾选 ====================

  /// 勾选 / 取消一本教材。
  void setBookSelected(String bookId, {required bool selected}) {
    _selection.setBook(bookId, selected: selected);
    notifyListeners();
  }

  /// 全选 / 全不选某个分类的整棵子树。
  void setNodeSelected(String nodeId, {required bool selected}) {
    _selection.setNode(nodeId, selected: selected);
    notifyListeners();
  }

  /// 反选当前可见的全部教材。
  void toggleAllVisible() {
    _selection.toggleAll(visibleBooks.map((Textbook book) => book.id));
    notifyListeners();
  }

  /// 清空勾选。
  void clearSelection() {
    if (_selection.isEmpty) {
      return;
    }
    _selection.clear();
    notifyListeners();
  }

  /// 已勾选的教材。
  ///
  /// 按索引顺序返回，而不是勾选顺序——下载队列的顺序应当稳定，
  /// 且与用户在列表里看到的顺序一致。
  List<Textbook> get selectedBooks => _index.items
      .where((Textbook book) => _selection.isSelected(book.id))
      .toList(growable: false);

  // ==================== 内部实现 ====================

  void _invalidateRows() {
    _cachedRows = null;
  }

  void _invalidateAll() {
    _cachedRows = null;
    _cachedResults = null;
  }

  /// 按展开状态把树拍平成行列表。
  ///
  /// 拍平后交给 `ListView.builder`，只构建视口内的十几行；
  /// 若用嵌套 `Column`，展开一个大分类就会一次性构建几千个 widget。
  List<BrowseRow> _buildRows() {
    final List<BrowseRow> rows = <BrowseRow>[];

    void visit(CatalogNode node) {
      rows.add(BrowseNodeRow(node));
      if (!_expanded.contains(node.id)) {
        return;
      }
      for (final CatalogNode child in node.children) {
        visit(child);
      }
      for (final Textbook book in node.books) {
        rows.add(BrowseBookRow(book, node.id, node.depth + 1));
      }
    }

    for (final CatalogNode root in _index.roots) {
      visit(root);
    }
    return rows;
  }
}
