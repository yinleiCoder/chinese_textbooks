import 'dart:convert';

import '../../entity/entity.dart';

/// 列定义。
///
/// 逐行对象的 JSON 里，键名会随每条记录重复出现——3565 条 × 6 个字段就是两万多次
/// 重复。改成**列式**（键名只出现一次，值按固定下标排列）后，体积降到原始分片的
/// 约 1/25，冷启动只读这份数据，完全不碰 10MB 的原始分片。
///
/// 下标顺序即契约：增删字段必须同时改 [CatalogShardCodec.schemaVersion]，
/// 否则旧数据会被按新格式解读，字段全部错位且不会报错。
abstract final class CatalogColumn {
  /// 教材 id（contentId）。
  static const int id = 0;

  /// 书名。
  static const int title = 1;

  /// 完整的 `tag_paths[0]`，tag_id 以 `/` 连接。
  ///
  /// 保留**完整**路径而不是预先裁掉前缀：要裁掉几段由数据决定（前两段是平台
  /// 固定的「教材 / 电子教材」），裁剪逻辑放在建索引时，存储层只做忠实记录。
  static const int tagPath = 2;

  /// 出版社名称。
  static const int providerName = 3;

  /// 封面预览图。
  static const int previewUrl = 4;

  /// 平台侧最后更新时间。
  static const int updateTime = 5;

  /// 列数。
  static const int count = 6;
}

/// 分片的编解码。
///
/// 每个清单分片（`part_*.json`）解析后**单独存一份**，而不是合并成一个大快照。
/// 这样某个分片更新时只需重新解析那一片，其余原样复用——
/// 平台每次更新往往只动其中一个分片，合并存储会让增量更新退化成整体重下。
final class CatalogShardCodec {
  const CatalogShardCodec._();

  /// 当前格式版本。
  ///
  /// 与 [CatalogColumn] 的下标顺序绑定：只增删字段也必须 +1。
  ///
  /// v2：封面来源从 `custom_properties.preview`（抽样内页）改成
  /// `thumbnails`（真正的封面）。改动列的含义同样要升版，
  /// 否则旧缓存会继续提供错误的封面。
  static const int schemaVersion = 2;

  /// 编码。
  static String encode(List<List<String>> rows) =>
      jsonEncode(<String, Object?>{'v': schemaVersion, 'rows': rows});

  /// 解码，格式不符或结构损坏时返回 `null`。
  ///
  /// 返回 `null` 时调用方应当重新下载该分片，而不是试图修复——
  /// 半截数据混进索引比重新下载昂贵得多。
  static List<List<String>>? decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['v'] != schemaVersion) {
      return null;
    }
    final Object? rawRows = decoded['rows'];
    if (rawRows is! List) {
      return null;
    }

    final List<List<String>> rows = <List<String>>[];
    for (final Object? row in rawRows) {
      if (row is! List || row.length < CatalogColumn.count) {
        return null;
      }
      rows.add(<String>[
        for (final Object? cell in row) cell is String ? cell : '',
      ]);
    }
    return rows;
  }

  /// 把一行还原成实体。
  static Textbook toTextbook(List<String> row) => Textbook(
    id: row[CatalogColumn.id],
    title: row[CatalogColumn.title],
    tagPath: row[CatalogColumn.tagPath].isEmpty
        ? const <String>[]
        : row[CatalogColumn.tagPath].split('/'),
    providerName: _nullIfEmpty(row[CatalogColumn.providerName]),
    previewUrl: _nullIfEmpty(row[CatalogColumn.previewUrl]),
    updateTime: _parseTime(row[CatalogColumn.updateTime]),
  );

  static String? _nullIfEmpty(String value) => value.isEmpty ? null : value;

  /// 宽容地解析时间。
  ///
  /// 平台用的是 `2026-08-18T11:38:05.668+0800`（带偏移但不带冒号），Dart 能解析。
  /// 但字段缺失或格式变动不该让整次构建失败——时间只用于标注新旧，
  /// 解析不出来就当没有。
  static DateTime? _parseTime(String value) =>
      value.isEmpty ? null : DateTime.tryParse(value);
}
