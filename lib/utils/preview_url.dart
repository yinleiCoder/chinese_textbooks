/// 从平台的书目/详情数据里挑出**封面**。
///
/// ## 平台有两组容易混淆的图
///
/// | 字段 | 内容 | 能否当封面 |
/// | --- | --- | --- |
/// | `custom_properties.thumbnails[0]` | 第 1 页（就是封面） | ✅ |
/// | `custom_properties.preview` | **抽样的一批内页**（`{SlideN: 第 N 页}`） | ❌ |
///
/// 实测一本 70 页的教材，`preview` 有 49 项、键是 `Slide6`/`Slide5`/`Slide8`
/// 这样的乱序页码——它给的是书籍内页的抽样，用来做预览浏览，
/// 拿它当封面会得到一堆内页。
///
/// 因此优先读 `thumbnails`；它缺失时才退回 `preview` 里序号最小的那张
/// （第 1 页），总比没有强。
String? pickCoverUrl({
  Object? thumbnails,
  Object? preview,
}) {
  final String? fromThumbnails = _firstOf(thumbnails);
  if (fromThumbnails != null) {
    return fromThumbnails;
  }
  return _lowestSlideOf(preview);
}

/// 取 `thumbnails` 数组里的第一张。
String? _firstOf(Object? thumbnails) {
  if (thumbnails is! List) {
    return null;
  }
  for (final Object? item in thumbnails) {
    if (item is String && item.isNotEmpty) {
      return item;
    }
  }
  return null;
}

/// 退路：`preview` 里页码最小的那张。
///
/// 键序不保证（实测出现过 Slide6、Slide5、Slide8），必须按序号挑。
String? _lowestSlideOf(Object? preview) {
  if (preview is! Map<String, dynamic> || preview.isEmpty) {
    return null;
  }
  String? best;
  int? bestIndex;
  for (final MapEntry<String, dynamic> entry in preview.entries) {
    final Object? value = entry.value;
    if (value is! String || value.isEmpty) {
      continue;
    }
    final Match? match = RegExp(r'(\d+)').firstMatch(entry.key);
    final int? index = match == null ? null : int.tryParse(match.group(1)!);
    if (index == null) {
      best ??= value;
      continue;
    }
    if (bestIndex == null || index < bestIndex) {
      bestIndex = index;
      best = value;
    }
  }
  return best;
}
