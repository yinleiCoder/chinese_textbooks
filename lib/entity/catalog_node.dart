import 'package:equatable/equatable.dart';

import 'textbook.dart';

/// 目录树上的一个分类节点。
///
/// ## 为什么 [id] 是路径而不是 tag_id
///
/// 平台的标签树**不是树，是 DAG**：同一个 tag_id 会在不同父节点下重复出现
/// （实测 185 个 tag_id 里有 101 个重复，「八年级」一个 id 出现 155 次）。
/// 若拿 tag_id 当节点身份，建立"id → 节点"的扁平映射时后出现的会覆盖先出现的，
/// 教材就会挂到错误的父节点下，子树计数与三态勾选随之全错。
///
/// 因此节点身份用**从根到本节点的 tag_id 路径**（`a/b/c`），它在树内唯一；
/// 原始的 [tagId] 单独保留，供筛选与展示使用。
///
/// 筛选按**维度**而不是按层号进行，同样是为了绕开这个问题：
/// 一个 tag 的 `tag_dimension_id` 是稳定的（「八年级」永远是 `zxxnj`），
/// 而"第几层是年级"并不稳定——标签树里各分支的深度并不一致。
final class CatalogNode extends Equatable {
  const CatalogNode({
    required this.id,
    required this.tagId,
    required this.label,
    required this.dimensionId,
    required this.depth,
    required this.parentId,
    required this.children,
    required this.books,
    required this.descendantBookIds,
  });

  /// 节点身份：从根到本节点的 tag_id 路径，树内唯一。
  final String id;

  /// 平台给的 tag_id。
  ///
  /// 会重复，因此不能作身份；用于筛选匹配与展示。
  final String tagId;

  /// 中文名，取自标签树。
  final String label;

  /// 平台给的维度 id（`zxxxd` / `zxxxk` / `zxxbb` / `zxxnj` / `zxxcc`）。
  final String? dimensionId;

  /// 在树中的层级，根节点为 0。
  final int depth;

  /// 父节点 id，根节点为 `null`。
  final String? parentId;

  /// 子分类。
  final List<CatalogNode> children;

  /// 直接挂在本节点下的教材（不含子分类的）。
  final List<Textbook> books;

  /// 整个子树内的全部教材 id，**建树时一次性算好**。
  ///
  /// 预计算让"全选某个分类"退化成一次 `Set.addAll`，
  /// 也让三态判断能 O(1) 拿到子树规模。
  final List<String> descendantBookIds;

  /// 子树内的教材总数。
  int get descendantBookCount => descendantBookIds.length;

  /// 是否有子分类。
  bool get hasChildren => children.isNotEmpty;

  /// 本节点下是否直接挂着教材。
  bool get hasBooks => books.isNotEmpty;

  /// 是否没有后代。
  ///
  /// 正常构建出的树不会有这种节点，出现即说明标签树与书目数据不一致。
  bool get isEmpty => children.isEmpty && books.isEmpty;

  @override
  List<Object?> get props => <Object?>[id, tagId, label, depth];

  @override
  String toString() =>
      'CatalogNode($id, $label, depth: $depth, books: $descendantBookCount)';
}

/// 一个筛选维度及其全部候选项。
///
/// 按**维度**而不是层号组织：标签树各分支的深度并不一致
/// （有的分支缺版本层、有的缺册次层），按层号对齐会把不同语义的东西混在一起。
/// 而 tag 的维度是稳定的。
final class CatalogFacet extends Equatable {
  const CatalogFacet({
    required this.dimensionId,
    required this.label,
    required this.options,
  });

  /// 平台维度 id。
  final String dimensionId;

  /// 展示名，如「学段」「学科」。
  final String label;

  /// 该维度下的候选项，按教材数量降序。
  final List<CatalogLevelOption> options;

  @override
  List<Object?> get props => <Object?>[dimensionId, label, options];
}

/// 筛选栏里的一个候选项。
final class CatalogLevelOption extends Equatable {
  const CatalogLevelOption({
    required this.tagId,
    required this.label,
    required this.bookCount,
  });

  /// 平台 tag_id。
  final String tagId;

  /// 中文名。
  final String label;

  /// 该 tag 下的教材数量（同一 tag 在树里出现多次时已合并）。
  final int bookCount;

  @override
  List<Object?> get props => <Object?>[tagId, label, bookCount];
}
