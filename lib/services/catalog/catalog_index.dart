import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../entity/entity.dart';
import '../../values/values.dart';
import 'catalog_filter.dart';
import 'catalog_snapshot_codec.dart';

/// 目录索引：树的骨架、筛选维度、以及查询所需的全部派生数据。
///
/// 构建一次、只读使用。所有数千量级的循环都在构建期完成。
///
/// ## 三个来自真实数据的硬约束
///
/// 1. **标签树是 DAG 不是树。** 同一个 tag_id 会在不同父节点下重复出现
///    （实测 185 个 id 里 101 个重复，「八年级」一个 id 出现 155 次）。
///    因此节点身份必须用**路径**，不能用 tag_id——否则"id → 节点"的扁平映射
///    会互相覆盖，教材挂错父节点，子树计数与三态勾选全错。
/// 2. **各分支深度不一致。** 有的分类没有版本层，有的没有册次层。
///    因此筛选按**维度**匹配，不按层号对齐。
/// 3. **标签树缺少书目引用到的节点。** 实测「册次」一层有约一半的 id
///    在树里找不到。走不通就停在当前层、把教材挂在那里，不能丢弃。
final class CatalogIndex {
  const CatalogIndex._({
    required this.roots,
    required this.items,
    required this.nodeById,
    required this.leafOwnerNodeId,
    required this.bookTagIds,
    required this.searchTexts,
    required this.facets,
    required this._indexById,
  });

  /// 可见的根节点。
  final List<CatalogNode> roots;

  /// 全部教材，顺序即快照顺序（稳定，可作下标空间）。
  final List<Textbook> items;

  /// 节点 id（路径）→ 节点。
  final Map<String, CatalogNode> nodeById;

  /// 教材 id → 它直接挂靠的节点 id。
  final Map<String, String> leafOwnerNodeId;

  /// **平行于 [items]**：每本教材分类链上的全部 tag_id。
  ///
  /// 用集合而不是列表：筛选只问"在不在里面"，不问顺序，
  /// 而顺序恰恰是深度不一致时最不可靠的信息。
  final List<Set<String>> bookTagIds;

  /// **平行于 [items]**：搜索用的拼接文本（已转小写）。
  final List<String> searchTexts;

  /// 各筛选维度及其候选项，按 `NdConfig.tagDimensionLabels` 的顺序排列。
  final List<CatalogFacet> facets;

  final Map<String, int> _indexById;

  /// 是否为空索引。
  bool get isEmpty => items.isEmpty;

  /// 教材总数。
  int get length => items.length;

  /// 按 id 取教材。
  ///
  /// 深链或热重启后 `GoRouterState.extra` 会丢失，页面要能靠 id 找回数据。
  Textbook? byId(String id) {
    final int? index = _indexById[id];
    return index == null ? null : items[index];
  }

  /// 教材的完整分类路径，如 `小学 › 语文 › 统编版 › 三年级 › 上册`。
  String categoryPathOf(Textbook book) {
    final String? ownerId = leafOwnerNodeId[book.id];
    if (ownerId == null) {
      return '';
    }
    final List<String> names = <String>[];
    CatalogNode? node = nodeById[ownerId];
    while (node != null) {
      if (node.label.isNotEmpty) {
        names.add(node.label);
      }
      final String? parentId = node.parentId;
      node = parentId == null ? null : nodeById[parentId];
    }
    return names.reversed.join(' › ');
  }

  /// 按筛选条件与关键词查询。
  ///
  /// 关键词按空白分词，要求**每个词都命中**同一本书的搜索文本（AND 语义），
  /// 与参考项目 `filter_resource_items` 的判定一致。
  List<Textbook> filterAndSearch(CatalogFilter filter, String query) {
    final List<String> terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((String term) => term.isNotEmpty)
        .toList(growable: false);

    if (filter.isEmpty && terms.isEmpty) {
      return items;
    }

    final List<Textbook> result = <Textbook>[];
    for (int i = 0; i < items.length; i++) {
      if (!_matchesFilter(i, filter)) {
        continue;
      }
      if (terms.isNotEmpty && !_matchesQuery(i, terms)) {
        continue;
      }
      result.add(items[i]);
    }
    return result;
  }

  bool _matchesFilter(int index, CatalogFilter filter) {
    if (filter.isEmpty) {
      return true;
    }
    final Set<String> tags = bookTagIds[index];
    for (final MapEntry<String, Set<String>> entry
        in filter.selectedByDimension.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      // 该维度下任一选中项出现在分类链里即命中。
      if (!entry.value.any(tags.contains)) {
        return false;
      }
    }
    return true;
  }

  bool _matchesQuery(int index, List<String> terms) {
    final String text = searchTexts[index];
    for (final String term in terms) {
      if (!text.contains(term)) {
        return false;
      }
    }
    return true;
  }

  // ==================== 构建 ====================

  /// 从分片行与标签树构建索引。
  ///
  /// 步骤与参考项目 `catalog.py` 一致：**先从标签树搭骨架**（这样每一层的
  /// 顺序是平台的教学顺序，而不是书目出现顺序），**再把教材挂到路径最深处**。
  /// 最后剪掉没有任何教材的分支，避免目录里出现点进去空空如也的分类。
  static CatalogIndex build({
    required List<List<String>> rows,
    required Map<String, dynamic> tagTreeJson,
  }) {
    final _TagSkeleton skeleton = _TagSkeleton.parse(tagTreeJson);

    final List<Textbook> items = <Textbook>[];
    final List<Set<String>> bookTagIds = <Set<String>>[];
    final Map<String, String> leafOwnerNodeId = <String, String>{};
    final Map<String, int> indexById = <String, int>{};

    for (final List<String> row in rows) {
      final Textbook book = CatalogShardCodec.toTextbook(row);
      if (book.tagPath.length < 2) {
        continue;
      }

      // 按**路径**逐层下钻，而不是查全局的 id → 节点表。
      // 标签树是 DAG，同一个 id 可能挂在多个父节点下，
      // 按 id 查会随机落到其中一份，教材就挂错了地方。
      _Builder? current;
      final List<String> chain = <String>[];
      List<_Builder> level = skeleton.roots;
      for (int i = 1; i < book.tagPath.length; i++) {
        final String tagId = book.tagPath[i];
        // 只认**本层的直接子节点**，找不到就停在这一层。
        //
        // 这里曾经有一条"退回全局查找"的兜底（`?? skeleton.byId[tagId]`），
        // 理由是标签树是 DAG、册次只挂在某一个「年级」副本下，不兜底的话
        // 教材几乎都走不到册次。实测证明这个兜底是有害的：
        //
        // 平台给**整库**的「上册」用同一个 tag_id（`…f883db0453`，847 本），
        // 而这个 id 在标签树里只挂在 `小学 › 英语 › 外研社版 › 五年级` 一处。
        // 于是所有学科的「上册」都被兜底搬到了那个节点底下——数学的、地理的、
        // 高中的全挤在小学英语里；而它们本该待着的「年级」节点上只剩「下册」
        // （下册的 tag_id 压根不在树里，反而老老实实停在了年级）。
        // 用户看到的就是"目录里只有下册，搜索出来的书层级对不上"。
        //
        // 停在能确定的最深一层，比"挂到语义无关的分类下"要好得多：
        // 册次本来也写在书名里，少一层不影响找书。
        final _Builder? next = _findChild(level, tagId);
        if (next == null) {
          // 标签树里确实没有这个 tag（平台数据缺节点）就停在当前层，
          // 把教材挂在能确定的最深位置，而不是丢掉它。
          break;
        }
        current = next;
        chain.add(next.tagId);
        level = next.children;
      }

      // 至少要走到固定前缀之下的一层真实分类。
      // 只解析出「电子教材」这一层的条目没有任何分类归属，
      // 而顶层节点在只有一个时会被上提，这类条目会变成树里够不到的孤儿。
      if (current == null || chain.length < 2) {
        continue;
      }

      current.books.add(book);
      items.add(book);
      bookTagIds.add(chain.toSet());
      indexById[book.id] = items.length - 1;
    }

    skeleton.pruneEmpty();

    // 顶层若只剩一个节点（实际就是「电子教材」），上提一层：
    // 让用户少点一次，目录页直接展示学段。
    final List<_Builder> topLevel = skeleton.roots;
    final List<_Builder> visibleRoots = topLevel.length == 1
        ? topLevel.single.children
        : topLevel;

    // 路径必须在**上提之后**才算最终——可见根的路径从 `''` 起算，
    // 不带被上提掉的那一层。挂书时还不能确定上提与否（要等剪枝结果），
    // 所以这里挂完书再统一回填一次归属节点。
    _TagSkeleton.assignPaths(visibleRoots, '');
    for (final _Builder root in visibleRoots) {
      _fillOwnerNode(root, leafOwnerNodeId);
    }

    // 维度计数与筛选**用同一份数据**，否则界面上会出现"学段写着 1716 本、
    // 点进去只有 1174 本"这种对不上的情况。
    // 口径：分类链里含该 tag 的教材数；被上提掉的那一层不计入。
    final String? hoistedTagId = topLevel.length == 1
        ? topLevel.single.tagId
        : null;
    final Map<String, int> tagBookCounts = <String, int>{};
    for (final Set<String> tags in bookTagIds) {
      for (final String tagId in tags) {
        if (tagId == hoistedTagId) {
          continue;
        }
        tagBookCounts[tagId] = (tagBookCounts[tagId] ?? 0) + 1;
      }
    }

    final _Frozen frozen = _freeze(
      visibleRoots,
      parentPath: '',
      parentId: null,
      depth: 0,
    );

    return CatalogIndex._(
      roots: frozen.roots,
      items: items,
      nodeById: frozen.nodeById,
      leafOwnerNodeId: leafOwnerNodeId,
      bookTagIds: bookTagIds,
      searchTexts: _buildSearchTexts(
        items: items,
        tagIds: bookTagIds,
        names: skeleton.names,
      ),
      facets: _buildFacets(
        tagBookCounts: tagBookCounts,
        names: skeleton.names,
        dimensions: skeleton.dimensions,
      ),
      indexById: indexById,
    );
  }

  /// 在给定的一层节点里按 tag_id 找子节点。
  ///
  /// 只在**直接子节点**里找，因此天然不会跨分支误配。
  static _Builder? _findChild(List<_Builder> level, String tagId) {
    for (final _Builder node in level) {
      if (node.tagId == tagId) {
        return node;
      }
    }
    return null;
  }

  /// 在后台 isolate 中从磁盘构建索引。
  static Future<CatalogIndex> buildInBackground({
    required List<String> shardPaths,
    required String tagTreePath,
  }) => Isolate.run(
    () => CatalogIndex.build(
      rows: _decodeShards(shardPaths),
      tagTreeJson: _decodeTagTree(tagTreePath),
    ),
  );

  /// 拼装搜索文本。
  ///
  /// 内容是"分类路径各层名称 + 书名 + 出版社"。
  /// **不含被上提掉的那一层**——「教材」「电子教材」出现在每一本书的路径里，
  /// 放进去只会让任何关键词都命中全部条目，等于没筛。
  static List<String> _buildSearchTexts({
    required List<Textbook> items,
    required List<Set<String>> tagIds,
    required Map<String, String> names,
  }) {
    final List<String> texts = <String>[];
    for (int i = 0; i < items.length; i++) {
      final StringBuffer buffer = StringBuffer();
      for (final String tagId in tagIds[i]) {
        final String name = names[tagId] ?? '';
        if (name.isNotEmpty) {
          buffer
            ..write(name)
            ..write(' ');
        }
      }
      buffer
        ..write(items[i].title)
        ..write(' ')
        ..write(items[i].providerName ?? '');
      texts.add(buffer.toString().toLowerCase());
    }
    return texts;
  }

  /// 汇总筛选维度。
  ///
  /// 计数口径与筛选**完全一致**：分类链里含该 tag 的教材数。
  ///
  /// 刻意不用"在树上累加各节点的子树教材数"那种写法：标签树是 DAG，
  /// 同一个 tag 有多个副本，而走树的兜底逻辑可能让一本教材的链上出现
  /// 重复 tag，累加就会重复计数——界面上表现为"学段写着 1716 本，
  /// 点进去只有 1174 本"。用同一份数据算，两边永远对得上。
  static List<CatalogFacet> _buildFacets({
    required Map<String, int> tagBookCounts,
    required Map<String, String> names,
    required Map<String, String?> dimensions,
  }) {
    final Map<String, List<CatalogLevelOption>> grouped =
        <String, List<CatalogLevelOption>>{};
    for (final MapEntry<String, int> entry in tagBookCounts.entries) {
      final String? dimensionId = dimensions[entry.key];
      if (dimensionId == null) {
        continue;
      }
      grouped
          .putIfAbsent(dimensionId, () => <CatalogLevelOption>[])
          .add(
            CatalogLevelOption(
              tagId: entry.key,
              label: names[entry.key] ?? entry.key,
              bookCount: entry.value,
            ),
          );
    }

    final List<CatalogFacet> facets = <CatalogFacet>[];
    void addFacet(String dimensionId, String label) {
      final List<CatalogLevelOption>? options = grouped.remove(dimensionId);
      if (options == null || options.isEmpty) {
        return;
      }
      options.sort(
        (CatalogLevelOption a, CatalogLevelOption b) =>
            b.bookCount.compareTo(a.bookCount),
      );
      facets.add(
        CatalogFacet(dimensionId: dimensionId, label: label, options: options),
      );
    }

    for (final MapEntry<String, String> entry
        in NdConfig.tagDimensionLabels.entries) {
      addFacet(entry.key, entry.value);
    }
    // 未知维度兜底，用 id 当展示名。
    for (final String dimensionId in grouped.keys.toList()) {
      addFacet(dimensionId, dimensionId);
    }
    return facets;
  }
}

/// 冻结一棵构建期节点树。
///
/// 节点身份用**路径**：标签树是 DAG，同一个 tag_id 会在多处出现，
/// 只有路径在树内唯一。
_Frozen _freeze(
  List<_Builder> builders, {
  required String parentPath,
  required String? parentId,
  required int depth,
}) {
  final List<CatalogNode> nodes = <CatalogNode>[];
  final Map<String, CatalogNode> byId = <String, CatalogNode>{};

  for (final _Builder builder in builders) {
    // 复用 [assignPaths] 算好的路径，不在这里重算——
    // 两处各算一遍迟早会因为某一处改了规则而对不上，
    // 而 `nodeById` 的键与 `leafOwnerNodeId` 的值必须严格一致。
    final String path = builder.path;
    final _Frozen childResult = _freeze(
      builder.children,
      parentPath: path,
      parentId: path,
      depth: depth + 1,
    );
    final CatalogNode node = CatalogNode(
      id: path,
      tagId: builder.tagId,
      label: builder.label,
      dimensionId: builder.dimensionId,
      depth: depth,
      parentId: parentId,
      children: childResult.roots,
      books: List<Textbook>.unmodifiable(builder.books),
      descendantBookIds: List<String>.unmodifiable(<String>[
        ...builder.books.map((Textbook book) => book.id),
        ...childResult.childDescendantIds,
      ]),
    );
    nodes.add(node);
    byId[path] = node;
    byId.addAll(childResult.nodeById);
  }

  return _Frozen(
    roots: List<CatalogNode>.unmodifiable(nodes),
    nodeById: byId,
    childDescendantIds: <String>[
      for (final CatalogNode node in nodes) ...node.descendantBookIds,
    ],
  );
}

/// 回填每本教材的归属节点。
///
/// 单列成顶层函数而不是在 `build` 里内联递归：`build` 已经很长，
/// 而这段逻辑与"路径最终确定"这件事强绑定，单独放更好读。
void _fillOwnerNode(_Builder node, Map<String, String> into) {
  for (final Textbook book in node.books) {
    into[book.id] = node.path;
  }
  for (final _Builder child in node.children) {
    _fillOwnerNode(child, into);
  }
}

final class _Frozen {
  const _Frozen({
    required this.roots,
    required this.nodeById,
    required this.childDescendantIds,
  });

  final List<CatalogNode> roots;
  final Map<String, CatalogNode> nodeById;
  final List<String> childDescendantIds;
}

/// 构建期的可变节点。
///
/// [path] 在冻结阶段才确定，构建期只用 [tagId] 做层内匹配。
final class _Builder {
  _Builder({
    required this.tagId,
    required this.label,
    required this.dimensionId,
  });

  final String tagId;
  final String label;
  final String? dimensionId;
  final List<_Builder> children = <_Builder>[];
  final List<Textbook> books = <Textbook>[];

  /// 冻结后的唯一路径，仅用于回填 [CatalogIndex.leafOwnerNodeId]。
  String path = '';

  /// 递归剪掉没有任何教材的分支，返回自身是否应当保留。
  bool pruneEmpty() {
    children.removeWhere((_Builder child) => !child.pruneEmpty());
    return books.isNotEmpty || children.isNotEmpty;
  }

  /// 冻结时回填路径。
  void assignPath(String value) => path = value;
}

/// 标签树的骨架。
final class _TagSkeleton {
  _TagSkeleton._({
    required this.roots,
    required this.names,
    required this.dimensions,
  });

  /// 顶层节点。
  final List<_Builder> roots;

  /// tag_id → 中文名。
  ///
  /// 同一个 tag_id 在所有出现处名称一致（实测成立），因此扁平映射是安全的。
  final Map<String, String> names;

  /// tag_id → 维度 id。同样与出现位置无关。
  final Map<String, String?> dimensions;

  /// tag_id → 首次出现的节点。
  ///
  /// 仅作为**位置查找失败时的兜底**。标签树是 DAG，同一 tag 有多份副本，
  /// 而子节点只挂在其中一份下面；严格按位置走会让大部分教材在中途断掉。
  final Map<String, _Builder> byId = <String, _Builder>{};

  /// 解析 `tch_material_tag.json` 并搭好骨架。
  static _TagSkeleton parse(Map<String, dynamic> tagTreeJson) {
    final _TagSkeleton skeleton = _TagSkeleton._(
      roots: <_Builder>[],
      names: <String, String>{},
      dimensions: <String, String?>{},
    );
    _parseGroups(
      tagTreeJson['hierarchies'],
      into: skeleton.roots,
      byId: skeleton.byId,
      names: skeleton.names,
      dimensions: skeleton.dimensions,
    );
    return skeleton;
  }

  /// 递归剪掉没有任何教材的分支。
  void pruneEmpty() {
    roots.removeWhere((_Builder child) => !child.pruneEmpty());
  }

  /// 回填节点路径。
  ///
  /// **必须在剪枝与上提之后调用**：路径里不该带上被上提掉的那一层
  /// （「电子教材」），也不该包含已被剪掉的空分支。
  static void assignPaths(List<_Builder> nodes, String parentPath) {
    for (final _Builder node in nodes) {
      final String path = parentPath.isEmpty
          ? node.tagId
          : '$parentPath/${node.tagId}';
      node.assignPath(path);
      assignPaths(node.children, path);
    }
  }

  /// 解析一层子节点。
  ///
  /// **注意这里有个容易踩空的结构**：`hierarchies` 的每个元素是**分组**
  /// （只有 `hierarchy_name` 与 `children`），真正的 tag 节点在分组的
  /// `children[]` 里，而每个节点又用自己的 `hierarchies` 放下一层分组。
  /// 层级是 `分组 → 节点 → 分组 → 节点` 交替的。
  ///
  /// 直接把 `hierarchies[i]` 当节点读，会因为分组没有 `tag_id` 而整层落空——
  /// 表现为书目一条都挂不上、索引空空如也，却不会有任何报错。
  static void _parseGroups(
    Object? groups, {
    required List<_Builder> into,
    required Map<String, _Builder> byId,
    required Map<String, String> names,
    required Map<String, String?> dimensions,
  }) {
    if (groups is! List) {
      return;
    }
    for (final Object? group in groups) {
      if (group is! Map<String, dynamic>) {
        continue;
      }
      final Object? children = group['children'];
      if (children is! List) {
        continue;
      }
      for (final Object? child in children) {
        final _Builder? node = _parseNode(
          child,
          byId: byId,
          names: names,
          dimensions: dimensions,
        );
        if (node != null) {
          into.add(node);
        }
      }
    }
  }

  static _Builder? _parseNode(
    Object? raw, {
    required Map<String, _Builder> byId,
    required Map<String, String> names,
    required Map<String, String?> dimensions,
  }) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final Object? id = raw['tag_id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final Object? name = raw['tag_name'];
    final Object? dimension = raw['tag_dimension_id'];
    final String label = name is String ? name : '';
    final _Builder node = _Builder(
      tagId: id,
      label: label,
      dimensionId: dimension is String ? dimension : null,
    );
    names[id] = label;
    dimensions[id] = dimension is String ? dimension : null;
    // 首次出现优先：兜底查找要的是稳定结果，不是"最后一个"。
    byId.putIfAbsent(id, () => node);

    _parseGroups(
      raw['hierarchies'],
      into: node.children,
      byId: byId,
      names: names,
      dimensions: dimensions,
    );
    return node;
  }
}

// ==================== 供 isolate 使用的读取器 ====================

/// 依次解码全部分片，拼成一份行数据。
///
/// **串行**推进是刻意的：同时解码多份会让中间对象图叠加，低端 Android 容易 OOM。
///
/// 与 [_decodeTagTree] 一样是**顶层函数**：`Isolate.run` 的闭包只能捕获
/// 可跨 isolate 发送的对象，顶层函数最省心。
List<List<String>> _decodeShards(List<String> paths) {
  final List<List<String>> rows = <List<String>>[];
  for (final String path in paths) {
    final List<List<String>>? shard = CatalogShardCodec.decode(_readFile(path));
    if (shard != null) {
      rows.addAll(shard);
    }
  }
  return rows;
}

/// 解码标签树文件。
Map<String, dynamic> _decodeTagTree(String path) {
  final Object? decoded = _decodeJson(_readFile(path));
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
}

/// 读文件内容。
String _readFile(String path) => File(path).readAsStringSync();

/// 解析 JSON，格式非法时返回 `null` 交由调用方兜底。
Object? _decodeJson(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}
