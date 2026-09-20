import 'dart:convert';

import 'package:chinese_textbooks/services/catalog/catalog.dart';

/// 目录层的测试夹具。
///
/// 手工构造一棵**形状确定**的小目录树，而不是拿线上数据：真实数据有 3565 条、
/// 层级深浅不一，一旦断言失败很难看出是哪一层错了。
///
/// 树形（括号内是 tag_id）：
/// ```
/// 教材(t-jc)                     ← 无教材，应被剪掉
/// 电子教材(t-dzjc)                ← 唯一顶层节点，应被上提
/// └── 小学(t-xx)
///     ├── 语文(t-yw)
///     │   └── 统编版(t-tbb)
///     │       └── 一年级(t-1nj)
///     │           ├── 上册(t-sc)   → A1, A2
///     │           └── 下册(t-xc)   → A3
///     └── 数学(t-sx)
///         └── 人教版(t-rjb)
///             └── 一年级(t-1nj2)
///                 └── 上册(t-sc2)  → B1
/// └── 初中(t-cz)
///     └── 语文(t-yw2)
///         └── 统编版(t-tbb2)
///             └── 七年级(t-7nj)
///                 └── 上册(t-sc3)  → C1
/// ```
///
/// 另有两条**应当被跳过**的脏数据：`tag_paths` 为空数组的、以及路径只到一半的。
const String kBookA1 = 'book-a1';
const String kBookA2 = 'book-a2';
const String kBookA3 = 'book-a3';
const String kBookB1 = 'book-b1';
const String kBookC1 = 'book-c1';

/// 节点 id 是**从可见根算起的 tag_id 路径**，不是 tag_id 本身。
///
/// 平台的标签树是 DAG（同一个 tag_id 在多个父节点下重复出现），
/// 只有路径能唯一标识一个节点。详见 `CatalogNode.id` 的注释。
///
/// 顶层节点的路径就是自己的 tag_id（「电子教材」被上提掉了，不占一层）。
const String kNodePrimary = 't-xx';

/// 语文。
const String kNodeChinese = 't-xx/t-yw';

/// 一年级（语文下）。
const String kNodeGrade1 = 't-xx/t-yw/t-tbb/t-1nj';

/// 语文一年级上册。
const String kNodePrimaryChineseGrade1Volume1 = 't-xx/t-yw/t-tbb/t-1nj/t-sc';

/// 数学一年级上册。
const String kNodeMathGrade1Volume1 = 't-xx/t-sx/t-rjb/t-1nj2/t-sc2';

/// 初中。
const String kNodeJunior = 't-cz';

/// 初中语文七年级上册。
const String kNodeJuniorChineseGrade7Volume1 =
    't-cz/t-yw2/t-tbb2/t-7nj/t-sc3';

/// 构造夹具。
({List<List<String>> rows, Map<String, dynamic> tagTree}) buildCatalogFixture() {
  return (
    rows: <List<String>>[
      _row(kBookA1, '义务教育教科书·语文一年级上册', 't-jc/t-dzjc/t-xx/t-yw/t-tbb/t-1nj/t-sc', '人民教育出版社'),
      _row(kBookA2, '义务教育教科书·语文一年级上册（大字版）', 't-jc/t-dzjc/t-xx/t-yw/t-tbb/t-1nj/t-sc', '人民教育出版社'),
      _row(kBookA3, '义务教育教科书·语文一年级下册', 't-jc/t-dzjc/t-xx/t-yw/t-tbb/t-1nj/t-xc', '人民教育出版社'),
      _row(kBookB1, '义务教育教科书·数学一年级上册', 't-jc/t-dzjc/t-xx/t-sx/t-rjb/t-1nj2/t-sc2', '人民教育出版社'),
      _row(kBookC1, '义务教育教科书·语文七年级上册', 't-jc/t-dzjc/t-cz/t-yw2/t-tbb2/t-7nj/t-sc3', '人民教育出版社'),
      // 脏数据：tag_paths 为空数组，应被跳过。
      <String>['book-empty-path', '没有分类的条目', '', '未知出版社', '', ''],
      // 脏数据：路径只有固定前缀，走不到任何真实节点，应被跳过。
      _row('book-short-path', '路径不完整的条目', 't-jc/t-dzjc', '未知出版社'),
    ],
    tagTree: _tagTree(),
  );
}

/// 构造索引。
CatalogIndex buildCatalogIndex() {
  final ({List<List<String>> rows, Map<String, dynamic> tagTree}) fixture =
      buildCatalogFixture();
  return CatalogIndex.build(
    rows: fixture.rows,
    tagTreeJson: fixture.tagTree,
  );
}

List<String> _row(String id, String title, String tagPath, String provider) =>
    <String>[id, title, tagPath, provider, '', '2026-08-18T11:38:05.668+0800'];

Map<String, dynamic> _tagTree() => <String, dynamic>{
  // 顶层：分组列表 → 分组 → 节点
  'hierarchies': <dynamic>[
    <String, dynamic>{
      'hierarchy_name': '电子教材',
      'children': <dynamic>[
        _tag('t-jc', '教材', 'tagView', <dynamic>[
          _tag('t-xx0', '小学', 'zxxxd', <dynamic>[]),
        ]),
        _tag('t-dzjc', '电子教材', '5036342742', <dynamic>[
          _tag('t-xx', '小学', 'zxxxd', <dynamic>[
            _tag('t-yw', '语文', 'zxxxk', <dynamic>[
              _tag('t-tbb', '统编版', 'zxxbb', <dynamic>[
                _tag('t-1nj', '一年级', 'zxxnj', <dynamic>[
                  _tag('t-sc', '上册', 'zxxcc', <dynamic>[]),
                  _tag('t-xc', '下册', 'zxxcc', <dynamic>[]),
                ]),
              ]),
            ]),
            _tag('t-sx', '数学', 'zxxxk', <dynamic>[
              _tag('t-rjb', '人教版', 'zxxbb', <dynamic>[
                _tag('t-1nj2', '一年级', 'zxxnj', <dynamic>[
                  _tag('t-sc2', '上册', 'zxxcc', <dynamic>[]),
                ]),
              ]),
            ]),
          ]),
          _tag('t-cz', '初中', 'zxxxd', <dynamic>[
            _tag('t-yw2', '语文', 'zxxxk', <dynamic>[
              _tag('t-tbb2', '统编版', 'zxxbb', <dynamic>[
                _tag('t-7nj', '七年级', 'zxxnj', <dynamic>[
                  _tag('t-sc3', '上册', 'zxxcc', <dynamic>[]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ],
    },
  ],
};

/// 构造一个 tag 节点。
///
/// **层级是 `分组 → 节点 → 分组 → 节点` 交替的**，与线上一致：
/// `hierarchies` 的每个元素是分组（只有 `hierarchy_name` 与 `children`），
/// 真正的节点在分组的 `children[]` 里。
///
/// 夹具必须复刻这个形状，否则测试会全绿而线上一条都挂不上——
/// 这个坑真实发生过一次（见 `_TagSkeleton._parseGroups` 的注释）。
Map<String, dynamic> _tag(
  String id,
  String name,
  String dimension,
  List<dynamic> children,
) => <String, dynamic>{
  'tag_id': id,
  'tag_name': name,
  'tag_dimension_id': dimension,
  'hierarchies': <dynamic>[
    <String, dynamic>{'hierarchy_name': name, 'children': children},
  ],
};

/// 原始平台格式的书目数组 JSON。
///
/// 供"走完整链路"的测试使用：把这份文本当作平台返回的分片内容，
/// 依次经过解析、列式存储、索引构建，而不是直接跳过解析层。
String buildRawBooksJson() {
  final List<List<String>> rows = buildCatalogFixture().rows;
  final List<Map<String, dynamic>> books = <Map<String, dynamic>>[];
  for (final List<String> row in rows) {
    final String tagPath = row[CatalogColumn.tagPath];
    if (tagPath.isEmpty) {
      continue;
    }
    books.add(<String, dynamic>{
      'id': row[CatalogColumn.id],
      'title': row[CatalogColumn.title],
      'tag_paths': <String>[tagPath],
      'provider_list': <Map<String, dynamic>>[
        <String, dynamic>{'name': row[CatalogColumn.providerName]},
      ],
      'update_time': row[CatalogColumn.updateTime],
    });
  }
  return jsonEncode(books);
}

/// 原始平台格式的标签树 JSON。
String buildRawTagTreeJson() => jsonEncode(buildCatalogFixture().tagTree);
