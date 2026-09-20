import 'package:equatable/equatable.dart';

/// 目录的筛选条件。
///
/// 按**维度 id**（`zxxxd` / `zxxxk` / …）而不是层号组织。
///
/// 为什么不用层号：标签树各分支的深度并不一致（有的分类缺版本层、
/// 有的缺册次层），同一个层号在不同分支上对应的是不同语义的东西。
/// 拿层号做筛选键，用户勾「人教版」时会连带命中一批别的分类。
/// 而 tag 的维度是平台数据里稳定的属性。
///
/// 匹配规则：**该维度下任一选中项出现在教材的分类链里即算命中**。
/// 不要求它出现在某个固定层号上，理由同上。
///
/// 同一维度内是多选（或），维度之间是且。空集合表示该维度不设限——
/// **不要**用"选中全部选项"来表达不设限，那样平台新增分类后会把新分类排除在外。
final class CatalogFilter extends Equatable {
  const CatalogFilter({
    this.selectedByDimension = const <String, Set<String>>{},
  });

  /// 维度 id → 选中的 tag_id。
  final Map<String, Set<String>> selectedByDimension;

  /// 是否没有任何筛选条件。
  bool get isEmpty =>
      selectedByDimension.values.every((Set<String> ids) => ids.isEmpty);

  /// 某个维度选中的 tag_id。
  Set<String> selectedIn(String dimensionId) =>
      selectedByDimension[dimensionId] ?? const <String>{};

  /// 切换某个维度里某个选项的选中状态。
  CatalogFilter toggle(String dimensionId, String tagId) {
    final Map<String, Set<String>> next = <String, Set<String>>{
      for (final MapEntry<String, Set<String>> entry
          in selectedByDimension.entries)
        entry.key: <String>{...entry.value},
    };
    final Set<String> current = next[dimensionId] ?? <String>{};
    if (!current.remove(tagId)) {
      current.add(tagId);
    }
    if (current.isEmpty) {
      next.remove(dimensionId);
    } else {
      next[dimensionId] = current;
    }
    return CatalogFilter(selectedByDimension: next);
  }

  /// 清空某个维度。
  CatalogFilter clearDimension(String dimensionId) {
    if (!selectedByDimension.containsKey(dimensionId)) {
      return this;
    }
    return CatalogFilter(
      selectedByDimension: <String, Set<String>>{
        for (final MapEntry<String, Set<String>> entry
            in selectedByDimension.entries)
          if (entry.key != dimensionId) entry.key: entry.value,
      },
    );
  }

  /// 清空全部条件。
  CatalogFilter cleared() => const CatalogFilter();

  @override
  List<Object?> get props => <Object?>[
    selectedByDimension.length,
    ...selectedByDimension.entries.map(
      (MapEntry<String, Set<String>> e) => '${e.key}:${e.value.length}',
    ),
  ];

  @override
  String toString() =>
      'CatalogFilter(${selectedByDimension.entries.map((MapEntry<String, Set<String>> e) => '${e.key}=${e.value.length}').join(', ')})';
}
