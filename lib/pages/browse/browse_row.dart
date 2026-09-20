import '../../entity/entity.dart';

/// 目录页列表里的一行。
///
/// 树与扁平列表共用同一个行类型，因此渲染层只需要一个 `ListView.builder`，
/// 不用为两种模式各写一套列表。
sealed class BrowseRow {
  const BrowseRow();

  /// 稳定且唯一的 key。
  ///
  /// 节点用路径、教材用 id，两者都不会在筛选或展开状态变化时改变，
  /// 因此滚动位置与动画不会错乱。
  String get key;

  /// 缩进层级。
  int get depth;
}

/// 分类节点行（可展开、可三态勾选）。
final class BrowseNodeRow extends BrowseRow {
  const BrowseNodeRow(this.node);

  final CatalogNode node;

  @override
  String get key => 'node:${node.id}';

  @override
  int get depth => node.depth;
}

/// 教材行（只能勾选，不能展开）。
final class BrowseBookRow extends BrowseRow {
  const BrowseBookRow(this.book, this.ownerNodeId, this.depth);

  final Textbook book;

  /// 教材挂在哪个节点下，用于"全选这个分类"等操作。
  final String ownerNodeId;

  @override
  String get key => 'book:${book.id}';

  @override
  final int depth;
}
