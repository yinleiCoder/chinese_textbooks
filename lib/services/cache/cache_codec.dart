import 'dart:convert';

/// 缓存值的编解码器（策略模式）。
///
/// `CacheStore` 只认识 [String]，业务数据类型与字符串之间的转换由本类负责。
/// 把编解码独立出来而不是让实体自己实现 `toJson`/`fromJson`，是为了：
/// - 实体层不必知道"缓存"这件事，保持纯粹的数据模型；
/// - 同一个实体在不同缓存场景下可以选用不同的编解码策略。
abstract interface class CacheCodec<T> {
  /// 值 → 字符串。
  String encode(T value);

  /// 字符串 → 值。
  ///
  /// 数据损坏时应当抛出 [FormatException]，由 `CacheManager` 捕获并按"未命中"处理。
  T decode(String payload);
}

/// 原样透传，适用于本身就以字符串保存的数据（如 HTML 片段、纯文本）。
final class StringCacheCodec implements CacheCodec<String> {
  const StringCacheCodec();

  @override
  String encode(String value) => value;

  @override
  String decode(String payload) => payload;
}

/// 单个对象的 JSON 编解码。
///
/// ```dart
/// final codec = JsonCacheCodec<Textbook>(
///   fromJson: Textbook.fromJson,
///   toJson: (Textbook it) => it.toJson(),
/// );
/// ```
final class JsonCacheCodec<T> implements CacheCodec<T> {
  const JsonCacheCodec({required this.fromJson, required this.toJson});

  /// 从 JSON 对象构造实体。
  final T Function(Map<String, dynamic> json) fromJson;

  /// 实体转 JSON 对象。
  final Map<String, dynamic> Function(T value) toJson;

  @override
  String encode(T value) => jsonEncode(toJson(value));

  @override
  T decode(String payload) {
    final Object? decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('期望 JSON 对象，实际为 ${decoded.runtimeType}');
    }
    return fromJson(decoded);
  }
}

/// 对象列表的 JSON 编解码。
final class JsonListCacheCodec<T> implements CacheCodec<List<T>> {
  const JsonListCacheCodec({required this.fromJson, required this.toJson});

  /// 从 JSON 对象构造单个实体。
  final T Function(Map<String, dynamic> json) fromJson;

  /// 单个实体转 JSON 对象。
  final Map<String, dynamic> Function(T value) toJson;

  @override
  String encode(List<T> value) => jsonEncode(value.map(toJson).toList());

  @override
  List<T> decode(String payload) {
    final Object? decoded = jsonDecode(payload);
    if (decoded is! List) {
      throw FormatException('期望 JSON 数组，实际为 ${decoded.runtimeType}');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }
}

/// 任意 JSON 结构的编解码，用于结构不确定的响应（如配置下发）。
final class RawJsonCacheCodec implements CacheCodec<Object?> {
  const RawJsonCacheCodec();

  @override
  String encode(Object? value) => jsonEncode(value);

  @override
  Object? decode(String payload) => jsonDecode(payload);
}
