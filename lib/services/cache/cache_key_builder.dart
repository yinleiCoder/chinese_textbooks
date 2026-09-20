import 'package:dio/dio.dart';

import 'cache_request.dart';

/// 缓存键生成策略。
typedef CacheKeyBuilder = String Function(RequestOptions options);

/// 默认缓存键：`METHOD path?sortedQuery#identity`。
///
/// 设计要点：
/// - **查询参数排序**：`?a=1&b=2` 与 `?b=2&a=1` 语义相同，
///   不排序会生成两个键，白白浪费一份缓存空间；
/// - **不含 host**：应用只对接一个后端，去掉 host 可以让键更短、更易读，
///   排查问题时能直接把键贴到浏览器里验证；
/// - **附带身份标识**：同一接口在不同登录态下返回的数据不同，
///   不带身份会导致用户切换后读到上一个人的缓存；
/// - **不哈希**：键保持可读，调试时一眼能看出是哪次请求。
///   若键长成为问题（极长的查询串），再换成 `sha1` 截断即可。
String defaultCacheKeyBuilder(RequestOptions options) {
  final Uri uri = options.uri;
  final List<String> queryParts = uri.queryParametersAll.entries.map((
    MapEntry<String, List<String>> entry,
  ) {
    // 同一参数出现多次时（如 ?id=1&id=2）也要保证顺序稳定。
    final List<String> values = entry.value.toList()..sort();
    return '${entry.key}=${values.join(',')}';
  }).toList()..sort();

  final StringBuffer buffer = StringBuffer()
    ..write(options.method.toUpperCase())
    ..write(' ')
    ..write(uri.path);

  if (queryParts.isNotEmpty) {
    buffer
      ..write('?')
      ..write(queryParts.join('&'));
  }

  return '${buffer.toString()}#${options.cacheIdentity}';
}

/// 只按路径生成键，忽略查询参数。
///
/// 适用于"查询参数只影响分页、而缓存希望整表共用"的场景，
/// 一般不推荐——除非你确实清楚由此带来的语义差异。
String pathOnlyCacheKeyBuilder(RequestOptions options) =>
    '${options.method.toUpperCase()} ${options.uri.path}#${options.cacheIdentity}';
