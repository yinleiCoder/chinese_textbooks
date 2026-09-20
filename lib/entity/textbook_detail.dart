import 'package:equatable/equatable.dart';

/// 教材详情。
///
/// 数据来自 `.../ndrv2/resources/tch_material/details/{contentId}.json` 的 `ti_items`。
/// 提取规则对齐参考项目 `api.py:get_resource_info` 的**两轮查找**：
/// 先认 `ti_is_source_file == true`，没命中再按 `ti_file_flag` 兜底。
final class TextbookDetail extends Equatable {
  const TextbookDetail({
    required this.contentId,
    required this.title,
    required this.pdfMirrors,
    this.sizeBytes,
    this.pageCount,
    this.previewUrl,
    this.ebookMappingUrl,
    this.ebookId,
  });

  /// 教材 id，与 `Textbook.id` 一致。
  final String contentId;

  /// 书名。
  final String title;

  /// PDF 的镜像地址，按 r1 / r2 / r3 顺序排列。
  ///
  /// 三个地址路径完全相同，只有域名不同。**这里保留全部三个**，
  /// 供下载器轮换；参考项目只取第一个，属于可以白捡的容错。
  final List<Uri> pdfMirrors;

  /// 平台给出的文件字节数（`ti_size`）。
  ///
  /// 同时用作下载进度分母和完整性校验基准——实测它与响应的
  /// `Content-Length` 完全一致。
  final int? sizeBytes;

  /// 总页数。
  ///
  /// 取自 `custom_properties.requirements[]` 中 `name == "pagesize"` 的项。
  /// **不要用预览图数量推算**——预览图通常只给 9 张。
  final int? pageCount;

  /// 封面地址。
  final String? previewUrl;

  /// 章节映射文件的地址（`ti_file_flag == "ebook_mapping"`）。
  ///
  /// 本期只做整册下载，这个字段与 [ebookId] 是为二期的"按章节下载"预留：
  /// 下载该 txt 得到 `{ebook_id, mappings:[{node_id, page_number}]}`，
  /// 再用 `ebook_id` 请求 `.../national_lesson/trees/{ebook_id}.json` 拿完整目录，
  /// 合并页码后可注入 PDF 书签或按页码范围切分。
  final String? ebookMappingUrl;

  /// 章节树 id，来源同上。
  final String? ebookId;

  /// 是否拿到了可下载的 PDF。
  ///
  /// 为 `false` 说明这本教材在清单里存在、但详情里没有源文件
  /// （常见于只有子资源的条目），界面应显示"暂不提供在线阅读"。
  bool get isDownloadable => pdfMirrors.isNotEmpty;

  /// 文件大小的可读形式，如 `21.6 MB`。
  String get readableSize {
    final int? bytes = sizeBytes;
    if (bytes == null || bytes <= 0) {
      return '未知大小';
    }
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  /// 主地址（第一个镜像）。
  Uri? get primaryMirror => pdfMirrors.isEmpty ? null : pdfMirrors.first;

  /// 派生新实例。
  TextbookDetail copyWith({
    List<Uri>? pdfMirrors,
    int? sizeBytes,
    int? pageCount,
    String? previewUrl,
    String? ebookMappingUrl,
    String? ebookId,
  }) => TextbookDetail(
    contentId: contentId,
    title: title,
    pdfMirrors: pdfMirrors ?? this.pdfMirrors,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    pageCount: pageCount ?? this.pageCount,
    previewUrl: previewUrl ?? this.previewUrl,
    ebookMappingUrl: ebookMappingUrl ?? this.ebookMappingUrl,
    ebookId: ebookId ?? this.ebookId,
  );

  @override
  List<Object?> get props => <Object?>[
    contentId,
    title,
    pdfMirrors,
    sizeBytes,
    pageCount,
    previewUrl,
    ebookMappingUrl,
    ebookId,
  ];

  @override
  String toString() =>
      'TextbookDetail($contentId, mirrors: ${pdfMirrors.length}, '
      'size: $readableSize, pages: $pageCount)';
}
