import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/services/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「上册」这个标签，平台给**整库**用同一个 tag_id，而它在标签树里
/// 只挂在某一个分支下（实测挂在 `小学 › 英语 › 外研社版 › 五年级`）。
/// 曾经为了"让教材能走到册次这一层"，索引在本层找不到 tag 时会退回全局查找——
/// 结果把各学科的「上册」全搬进了小学英语，而它们本该待着的年级节点上
/// 只剩「下册」（下册的 tag_id 压根不在树里，反而老老实实停在了年级）。
///
/// 这个夹具把那份线上数据原样缩小复刻：**树里只有一个「上册」节点，
/// 且不在数学那条分支上**。
void main() {
  /// 平台固定的前缀：教材 / 电子教材。
  const String prefix = 't-jc/t-dzjc';

  CatalogIndex buildIndex() => CatalogIndex.build(
    rows: <List<String>>[
      // 数学一年级上册：册次 tag 是树里那个**唯一**的「上册」节点。
      _row('math-up', '义务教育教科书·数学一年级上册', '$prefix/t-xx/t-sx/t-rjb/t-1nj/t-sc'),
      // 数学一年级下册：册次 tag 树里根本没有。
      _row('math-down', '义务教育教科书·数学一年级下册', '$prefix/t-xx/t-sx/t-rjb/t-1nj/t-xc'),
    ],
    tagTreeJson: _tagTree(),
  );

  test('本层找不到的 tag 不会退到全局：上册留在数学，不搬到英语', () {
    final CatalogIndex index = buildIndex();

    final Textbook up = index.byId('math-up')!;
    expect(
      index.categoryPathOf(up),
      '小学 › 数学 › 人教版 › 一年级',
      reason: '上册的 tag 虽在树里，但不在数学这一支下——不该被搬走',
    );
  });

  test('上下册落在同一个年级节点下，成对出现', () {
    final CatalogIndex index = buildIndex();

    final Textbook up = index.byId('math-up')!;
    final Textbook down = index.byId('math-down')!;

    expect(index.categoryPathOf(up), index.categoryPathOf(down));
    expect(
      index.leafOwnerNodeId[up.id],
      index.leafOwnerNodeId[down.id],
      reason: '同一册次的书应当挂在同一个节点上',
    );
  });

  test('没人引用的那个「上册」节点被剪掉，不会留下一片空分类', () {
    final CatalogIndex index = buildIndex();

    // 英语那一支没有任何教材，整支都该被剪掉。
    expect(
      index.nodeById.keys.where((String id) => id.contains('t-yy')),
      isEmpty,
    );
  });
}

List<String> _row(String id, String title, String tagPath) => <String>[
  id,
  title,
  tagPath,
  '人民教育出版社',
  '',
  '2026-08-18T11:38:05.668+0800',
];

/// 复刻线上形状：`hierarchies` 的每个元素是**分组**（只有名字与 children），
/// 真正的节点在分组的 `children[]` 里，节点自己的下一层又是 `hierarchies`。
Map<String, dynamic> _tagTree() => <String, dynamic>{
  'hierarchies': <dynamic>[
    <String, dynamic>{
      'hierarchy_name': '电子教材',
      'children': <dynamic>[
        _tag('t-jc', '教材', <dynamic>[
          _tag('t-xx0', '小学', <dynamic>[]),
        ]),
        _tag('t-dzjc', '电子教材', <dynamic>[
          _tag('t-xx', '小学', <dynamic>[
            // 数学这一支：一年级下面**没有**册次节点。
            _tag('t-sx', '数学', <dynamic>[
              _tag('t-rjb', '人教版', <dynamic>[
                _tag('t-1nj', '一年级', <dynamic>[]),
              ]),
            ]),
            // 全树唯一的「上册」挂在这里。
            _tag('t-yy', '英语', <dynamic>[
              _tag('t-wy', '外研社版', <dynamic>[
                _tag('t-5nj', '五年级', <dynamic>[
                  _tag('t-sc', '上册', <dynamic>[]),
                ]),
              ]),
            ]),
          ]),
        ]),
      ],
    },
  ],
};

Map<String, dynamic> _tag(String id, String name, List<dynamic> children) =>
    <String, dynamic>{
      'tag_id': id,
      'tag_name': name,
      'tag_dimension_id': 'd-$id',
      'hierarchies': <dynamic>[
        <String, dynamic>{'hierarchy_name': name, 'children': children},
      ],
    };
