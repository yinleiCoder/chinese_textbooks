import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'cache_entry.g.dart';

/// 缓存条目：**值 + 元数据**的统一载体。
///
/// 把元数据和值打包在一起，是让 `CacheStore` 的各层实现
/// （内存 / 磁盘 / 组合）能以同一种结构互相传递、互相回填的前提。
///
/// 字段语义：
/// - [expiresAt] 只描述**新鲜度**，过期的条目仍然可以被读到——
///   离线兜底与 `staleWhileRevalidate` 正需要读到过期数据；
/// - 条目的**物理删除**由 `CacheStore.evictExpired` 依据保留期统一执行；
/// - [etag] / [lastModified] 用于发起条件请求，命中 304 时可直接复用本地数据，
///   省下一次完整的响应体传输。
@JsonSerializable()
final class CacheEntry extends Equatable {
  const CacheEntry({
    required this.key,
    required this.payload,
    required this.createdAt,
    required this.expiresAt,
    this.lastAccessedAt,
    this.etag,
    this.lastModified,
    this.metadata = const <String, String>{},
  });

  /// 从 JSON 还原。
  factory CacheEntry.fromJson(Map<String, dynamic> json) =>
      _$CacheEntryFromJson(json);

  /// 缓存键，由 `CacheKeyBuilder` 生成。
  final String key;

  /// 已编码的原始值。
  ///
  /// 保存字符串而不是 `Object`，是为了让内存层与磁盘层共用同一份表示，
  /// 回填时无需二次编解码。
  final String payload;

  /// 写入时间。
  final DateTime createdAt;

  /// 过期时间，超过之后 [isFresh] 为 `false`。
  final DateTime expiresAt;

  /// 最近一次被读取的时间，供 LRU 与磁盘淘汰策略使用。
  final DateTime? lastAccessedAt;

  /// HTTP 响应头 `ETag`。
  final String? etag;

  /// HTTP 响应头 `Last-Modified`。
  final String? lastModified;

  /// 业务自定义的附加信息（如数据版本号），便于按需做精细化失效。
  final Map<String, String> metadata;

  /// 是否仍然新鲜。
  bool get isFresh => DateTime.now().isBefore(expiresAt);

  /// 是否已过期。
  bool get isExpired => !isFresh;

  /// 从写入到现在经过的时间。
  Duration get age => DateTime.now().difference(createdAt);

  /// 标记为"刚刚被访问"，返回新的实例（本类不可变）。
  CacheEntry touched() => copyWith(lastAccessedAt: DateTime.now());

  /// 判断该条目在 [maxStale] 之内是否还能作为降级数据使用。
  ///
  /// 传 `null` 表示不限制陈旧程度（只要没被物理删除就可用）。
  bool isUsableAsStale(Duration? maxStale) {
    if (maxStale == null) {
      return true;
    }
    return DateTime.now().isBefore(expiresAt.add(maxStale));
  }

  /// 派生新实例。
  ///
  /// 只暴露确实需要变更的字段，避免出现"传 `null` 到底是清空还是不改"的歧义。
  CacheEntry copyWith({
    String? payload,
    DateTime? expiresAt,
    DateTime? lastAccessedAt,
    String? etag,
    String? lastModified,
    Map<String, String>? metadata,
  }) => CacheEntry(
    key: key,
    payload: payload ?? this.payload,
    createdAt: createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    etag: etag ?? this.etag,
    lastModified: lastModified ?? this.lastModified,
    metadata: metadata ?? this.metadata,
  );

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => _$CacheEntryToJson(this);

  @override
  List<Object?> get props => <Object?>[
    key,
    payload,
    createdAt,
    expiresAt,
    lastAccessedAt,
    etag,
    lastModified,
    metadata,
  ];

  @override
  String toString() =>
      'CacheEntry(key: $key, createdAt: $createdAt, '
      'expiresAt: $expiresAt, expired: $isExpired)';
}
