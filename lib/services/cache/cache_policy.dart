import 'package:equatable/equatable.dart';

/// 缓存读取策略。
///
/// 取值参考了 HTTP 缓存与主流移动端缓存的通用做法，
/// 每种策略对应一个明确的"先看谁"的问题。
enum CacheStrategy {
  /// 只走网络：既读缓存也写缓存。
  ///
  /// 适用于登录、支付、实时库存这类**绝不能拿到旧数据**的接口。
  networkOnly,

  /// 只读缓存：没有缓存就直接失败。
  ///
  /// 适用于已明确预下载的内容（如已下载的课文音频）。
  cacheOnly,

  /// 缓存优先：缓存新鲜就用缓存，否则请求网络。
  ///
  /// 适用于内容型数据——绝大多数请求都能被缓存拦下，省流量也更快。
  cacheFirst,

  /// 网络优先：先请求网络，失败时回落到缓存（含过期缓存）。
  ///
  /// 适用于需要尽量保证时效、但断网时也要能看的场景。
  networkFirst,

  /// 陈旧返回 + 后台刷新（stale-while-revalidate）。
  ///
  /// 立即返回缓存内容保证首屏速度，同时在后台静默更新，
  /// 用户下一次进来就能看到新数据。适用于列表页、首页这类
  /// "稍微旧一点没关系、但必须马上出内容"的场景。
  staleWhileRevalidate,
}

/// 缓存策略值对象。
///
/// 不可变，可作为 `RequestOptions.extra` 的值安全传递，也可作为常量复用。
/// 预置策略见类末尾的静态常量，业务侧优先复用它们而不是每次现造一个，
/// 这样"哪些接口缓存多久"能在一处看清。
final class CachePolicy extends Equatable {
  const CachePolicy({
    required this.strategy,
    this.ttl = const Duration(minutes: 10),
    this.maxStale = const Duration(days: 1),
    this.persist = true,
  });

  /// 读取策略。
  final CacheStrategy strategy;

  /// 新鲜期。超过该时长后条目视为过期（但不会立刻被删除）。
  final Duration ttl;

  /// 最大陈旧期。
  ///
  /// 过期后仍允许作为降级数据使用的时间上限；传 `null` 表示不限制。
  final Duration? maxStale;

  /// 是否写入持久化层。
  ///
  /// 涉及个人隐私且无需离线可用的数据应当置为 `false`，只留在内存中。
  final bool persist;

  // ==================== 预置策略 ====================

  /// 不缓存。
  static const CachePolicy none = CachePolicy(
    strategy: CacheStrategy.networkOnly,
    ttl: Duration.zero,
    persist: false,
  );

  /// 仅内存缓存 5 分钟，不落盘。
  static const CachePolicy memoryOnly = CachePolicy(
    strategy: CacheStrategy.networkFirst,
    ttl: Duration(minutes: 5),
    persist: false,
  );

  /// 短缓存：2 分钟，缓存优先。适用于变动较频繁的列表。
  static const CachePolicy shortLived = CachePolicy(
    strategy: CacheStrategy.cacheFirst,
    ttl: Duration(minutes: 2),
  );

  /// 常规策略：网络优先，15 分钟新鲜期，断网回落到过期数据。
  static const CachePolicy standard = CachePolicy(
    strategy: CacheStrategy.networkFirst,
    ttl: Duration(minutes: 15),
  );

  /// 长缓存：12 小时，缓存优先。适用于教材目录、生字表等低频变更数据。
  static const CachePolicy longLived = CachePolicy(
    strategy: CacheStrategy.cacheFirst,
    ttl: Duration(hours: 12),
  );

  /// 离线优先：3 天新鲜期，最长可陈旧 30 天。
  ///
  /// 适用于已下载课文正文这类"必须能离线看"的内容。
  static const CachePolicy offlineFirst = CachePolicy(
    strategy: CacheStrategy.cacheFirst,
    ttl: Duration(days: 3),
    maxStale: Duration(days: 30),
  );

  /// 陈旧返回 + 后台刷新，适合首页与各类信息流。
  static const CachePolicy revalidate = CachePolicy(
    strategy: CacheStrategy.staleWhileRevalidate,
    ttl: Duration(minutes: 10),
  );

  /// 是否需要读取缓存。
  bool get readsCache => strategy != CacheStrategy.networkOnly;

  /// 是否需要写入缓存。
  ///
  /// [CacheStrategy.cacheOnly] 表示"缓存由别处预置"，本策略只读不写。
  bool get writesCache => switch (strategy) {
    CacheStrategy.networkOnly => false,
    CacheStrategy.cacheOnly => false,
    CacheStrategy.cacheFirst => true,
    CacheStrategy.networkFirst => true,
    CacheStrategy.staleWhileRevalidate => true,
  };

  /// 派生新策略，只覆盖需要变更的字段。
  CachePolicy copyWith({
    CacheStrategy? strategy,
    Duration? ttl,
    Duration? maxStale,
    bool? persist,
  }) => CachePolicy(
    strategy: strategy ?? this.strategy,
    ttl: ttl ?? this.ttl,
    maxStale: maxStale ?? this.maxStale,
    persist: persist ?? this.persist,
  );

  @override
  List<Object?> get props => <Object?>[strategy, ttl, maxStale, persist];

  @override
  String toString() =>
      'CachePolicy(${strategy.name}, ttl: ${ttl.inMinutes}min, '
      'maxStale: ${maxStale?.inHours ?? '∞'}h, persist: $persist)';
}
