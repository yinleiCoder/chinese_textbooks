import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'textbook.g.dart';

/// 一本教材。
///
/// **只承载平台清单接口返回的原始字段**，不做任何派生。分类名路径、搜索文本
/// 这类需要查标签树才能得到的信息由 `CatalogIndex` 另行维护——这样本类可以
/// 直接序列化进紧凑快照，索引重建时也不必回头改教材对象。
@JsonSerializable()
final class Textbook extends Equatable {
  const Textbook({
    required this.id,
    required this.title,
    required this.tagPath,
    this.providerName,
    this.previewUrl,
    this.updateTime,
  });

  /// 从 JSON 构造。
  factory Textbook.fromJson(Map<String, dynamic> json) =>
      _$TextbookFromJson(json);

  /// `contentId`，详情接口与缓存键都用它。
  final String id;

  /// 书名。
  final String title;

  /// 分类路径的 **tag_id** 序列。
  ///
  /// 来源是清单里的 `tag_paths[0]`，已去掉开头两段固定前缀（「教材」「电子教材」）。
  /// 保留 id 而不是名称，是因为树是按 id 挂载的；名称在展示时查标签树得到。
  final List<String> tagPath;

  /// 出版社，如「人民教育出版社」。重名教材加版别前缀时要用。
  final String? providerName;

  /// 封面预览图地址。
  final String? previewUrl;

  /// 平台侧最后更新时间。
  ///
  /// 官网前端另有一份硬编码的排除列表用来过滤被新版取代的旧教材，
  /// 本项目刻意不过滤（参考项目 issue #60），改为在列表里标注新旧，由用户自己判断。
  final DateTime? updateTime;

  /// 是否带有可展示的封面。
  bool get hasPreview => previewUrl != null && previewUrl!.isNotEmpty;

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => _$TextbookToJson(this);

  /// **只比较 [id]。**
  ///
  /// 全量有 3565 个实例，每次比较都过一遍 6 个字段（其中 `tagPath` 还是列表）
  /// 在列表滚动与集合运算里会明显变慢；而 id 在平台内唯一，
  /// 足以支撑相等语义与 `Set` / `Map` 的去重。
  @override
  List<Object?> get props => <Object?>[id];

  @override
  String toString() => 'Textbook($id, $title)';
}
