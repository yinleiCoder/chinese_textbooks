import 'package:equatable/equatable.dart';

/// 目录数据的清单，记录"本地已有哪些分片、它们的 ETag 是什么"。
///
/// **它是"本次可用"的唯一凭据，且最后写入。** 只有它写成功，前面下载与解析
/// 出来的分片才算数；中途失败时它还是旧内容，下次启动仍然读得到旧数据。
final class CatalogManifest extends Equatable {
  const CatalogManifest({
    required this.fetchedAt,
    required this.parts,
    this.tagEtag,
    this.moduleVersion,
  });

  /// 从 JSON 构造。
  static CatalogManifest? fromJson(Map<String, dynamic> json) {
    if (json['v'] != schemaVersion) {
      return null;
    }
    final Object? rawParts = json['parts'];
    if (rawParts is! List) {
      return null;
    }
    final List<CatalogPartEntry> parts = <CatalogPartEntry>[];
    for (final Object? raw in rawParts) {
      final CatalogPartEntry? entry = CatalogPartEntry.fromJson(raw);
      if (entry != null) {
        parts.add(entry);
      }
    }
    if (parts.isEmpty) {
      return null;
    }

    final Object? fetchedAt = json['fetchedAt'];
    final Object? moduleVersion = json['moduleVersion'];
    final Object? tagEtag = json['tagEtag'];
    return CatalogManifest(
      fetchedAt:
          (fetchedAt is String ? DateTime.tryParse(fetchedAt) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      parts: parts,
      tagEtag: tagEtag is String ? tagEtag : null,
      moduleVersion: moduleVersion is int ? moduleVersion : null,
    );
  }

  /// 当前格式版本。
  static const int schemaVersion = 1;

  /// 上次成功拉取的时间。
  final DateTime fetchedAt;

  /// 各分片的记录。
  final List<CatalogPartEntry> parts;

  /// 标签树文件的 ETag。
  final String? tagEtag;

  /// 平台给出的 `module_version`。
  ///
  /// **仅作诊断记录，不参与任何逻辑判断。** 实测它停在 2023-03-19 而内容更新到
  /// 2026-09——它和内容变更无关，拿它判断"要不要更新"会导致用户永远看不到新教材。
  /// 判断更新一律看各分片的 ETag。
  final int? moduleVersion;

  /// 全部分片的文件名。
  List<String> get shardFileNames => parts
      .map((CatalogPartEntry part) => part.fileName)
      .toList(growable: false);

  /// 教材总数。
  int get bookCount =>
      parts.fold(0, (int sum, CatalogPartEntry part) => sum + part.count);

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': schemaVersion,
    'fetchedAt': fetchedAt.toIso8601String(),
    if (tagEtag != null) 'tagEtag': tagEtag,
    if (moduleVersion != null) 'moduleVersion': moduleVersion,
    'parts': parts.map((CatalogPartEntry part) => part.toJson()).toList(),
  };

  @override
  List<Object?> get props => <Object?>[
    fetchedAt,
    parts,
    tagEtag,
    moduleVersion,
  ];
}

/// 单个分片的记录。
final class CatalogPartEntry extends Equatable {
  const CatalogPartEntry({
    required this.url,
    required this.fileName,
    required this.count,
    this.etag,
  });

  /// 从 JSON 构造。
  static CatalogPartEntry? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final Object? url = raw['url'];
    final Object? fileName = raw['file'];
    if (url is! String || fileName is! String) {
      return null;
    }
    final Object? etag = raw['etag'];
    final Object? count = raw['count'];
    return CatalogPartEntry(
      url: url,
      fileName: fileName,
      count: count is int ? count : 0,
      etag: etag is String ? etag : null,
    );
  }

  /// 分片的下载地址。
  final String url;

  /// 解析结果在本地存成的文件名。
  ///
  /// 用 URL 的哈希而不是序号：分片列表的顺序或数量变化时，
  /// 按序号命名会让内容与文件名错位，按 URL 命名则天然稳定。
  final String fileName;

  /// 该分片解析出的条目数。
  final int count;

  /// 下载时响应头里的 ETag，下次用来做条件请求。
  final String? etag;

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'file': fileName,
    'count': count,
    if (etag != null) 'etag': etag,
  };

  @override
  List<Object?> get props => <Object?>[url, fileName, count, etag];
}
