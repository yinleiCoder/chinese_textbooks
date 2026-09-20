import 'dart:convert';
import 'dart:io';

import '../../utils/utils.dart';
import 'catalog_snapshot_codec.dart';

/// 在后台 isolate 中解析一个清单分片，只抽取需要的列。
///
/// **必须是顶层函数**：`Isolate.run` 的闭包要能跨 isolate 发送，
/// 捕获了实例状态的闭包不行。
///
/// **为什么把路径传进来、让 isolate 自己读文件**：分片约 10MB，解码后
/// 展开出的中间对象可达上百 MB。让读取与解码全在后台 isolate 的堆里发生，
/// 主 isolate 只接收最终的精简行数据，就不会被这轮 GC 停顿波及。
///
/// 只处理一个分片：同时解码两个 10MB 分片，峰值内存会到 200MB 量级，
/// 低端 Android 会 OOM。调用方应当串行推进。
List<List<String>> parseCatalogPart(String filePath) {
  final String raw = File(filePath).readAsStringSync();
  final Object? decoded = jsonDecode(raw);
  if (decoded is! List) {
    return const <List<String>>[];
  }

  final List<List<String>> rows = <List<String>>[];
  for (final Object? item in decoded) {
    final List<String>? row = _toRow(item);
    if (row != null) {
      rows.add(row);
    }
  }
  return rows;
}

/// 把一条书目转成一行列数据，不可用时返回 `null`。
List<String>? _toRow(Object? item) {
  if (item is! Map<String, dynamic>) {
    return null;
  }

  final Object? id = item['id'];
  if (id is! String || id.isEmpty) {
    return null;
  }

  // tag_paths 为空数组的条目直接跳过。
  // 参考项目的注释写得很明确：「某些非课本资料的 tag_paths 属性为空数组」——
  // 这类条目没有分类归属，挂不进树，留着只会在"全选"时凭空多出无主条目。
  final Object? tagPaths = item['tag_paths'];
  if (tagPaths is! List || tagPaths.isEmpty) {
    return null;
  }
  final Object? tagPath = tagPaths.first;
  if (tagPath is! String || tagPath.isEmpty) {
    return null;
  }

  final List<String> row = List<String>.filled(CatalogColumn.count, '');
  row[CatalogColumn.id] = id;
  row[CatalogColumn.title] = _titleOf(item);
  row[CatalogColumn.tagPath] = tagPath;
  row[CatalogColumn.providerName] = _providerNameOf(item);
  row[CatalogColumn.previewUrl] = _previewUrlOf(item);
  row[CatalogColumn.updateTime] = _stringOf(item['update_time']);
  return row;
}

/// 取书名。
///
/// 优先 `global_title['zh-CN']`，其次 `title`。两者都缺时退回 id，
/// 保证列表里不会出现空白行——有 id 至少还能去详情页看。
String _titleOf(Map<String, dynamic> item) {
  final Object? globalTitle = item['global_title'];
  if (globalTitle is Map<String, dynamic>) {
    final String zh = _stringOf(globalTitle['zh-CN']);
    if (zh.isNotEmpty) {
      return zh;
    }
    final String en = _stringOf(globalTitle['en']);
    if (en.isNotEmpty) {
      return en;
    }
  }
  final String title = _stringOf(item['title']);
  return title.isNotEmpty ? title : _stringOf(item['id']);
}

/// 取出版社名称。
String _providerNameOf(Map<String, dynamic> item) {
  final Object? providers = item['provider_list'];
  if (providers is List && providers.isNotEmpty) {
    final Object? first = providers.first;
    if (first is Map<String, dynamic>) {
      return _stringOf(first['name']);
    }
  }
  return '';
}

/// 取封面。
///
/// **必须用 `thumbnails` 而不是 `preview`**：后者是抽样的一批内页，
/// 拿它当封面会得到一堆正文页。详见 `pickCoverUrl` 的注释。
String _previewUrlOf(Map<String, dynamic> item) {
  final Object? custom = item['custom_properties'];
  if (custom is Map<String, dynamic>) {
    return pickCoverUrl(
          thumbnails: custom['thumbnails'],
          preview: custom['preview'],
        ) ??
        '';
  }
  return '';
}

String _stringOf(Object? value) => value is String ? value : '';
