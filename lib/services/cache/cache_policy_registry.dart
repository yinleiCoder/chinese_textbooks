import 'cache_policy.dart';

/// 路径 → 缓存策略的注册表。
///
/// 把"哪些接口缓存多久"集中在一处声明，而不是散落在每个请求的 `Options` 里。
/// 好处是接口缓存策略一目了然，调整时也不用翻遍调用点。
///
/// 匹配规则按**注册顺序**生效，先注册的优先，因此应当把更具体的路径写在前面：
/// ```dart
/// final registry = CachePolicyRegistry(defaultPolicy: CachePolicy.none)
///   ..registerPrefix('${AppConfig.apiPrefix}/textbooks/', CachePolicy.longLived)
///   ..registerPrefix('${AppConfig.apiPrefix}/textbooks', CachePolicy.standard);
/// ```
final class CachePolicyRegistry {
  CachePolicyRegistry({this._defaultPolicy = CachePolicy.none});

  final CachePolicy _defaultPolicy;
  final List<_PolicyRule> _rules = <_PolicyRule>[];

  /// 默认策略，所有未命中规则的路径都使用它。
  ///
  /// 默认值刻意设为 [CachePolicy.none]：新增接口默认不缓存，
  /// 需要缓存必须显式声明。这样能避免"某个接口悄悄被缓存了"的意外。
  CachePolicy get defaultPolicy => _defaultPolicy;

  /// 按**路径前缀**注册策略。
  ///
  /// [pathPrefix] 会被 [RegExp.escape] 转义，因此可以安全传入含 `.`、`?` 的路径。
  void registerPrefix(String pathPrefix, CachePolicy policy) {
    _rules.add(
      _PolicyRule(
        pattern: RegExp('^${RegExp.escape(pathPrefix)}'),
        policy: policy,
      ),
    );
  }

  /// 按**正则表达式**注册策略，用于前缀无法表达的匹配（如带路径参数的 RESTful 路径）。
  ///
  /// ```dart
  /// registry.registerPattern(r'^/api/v1/textbooks/\d+$', CachePolicy.offlineFirst);
  /// ```
  void registerPattern(String pattern, CachePolicy policy) {
    _rules.add(_PolicyRule(pattern: RegExp(pattern), policy: policy));
  }

  /// 解析某个路径对应的策略。
  CachePolicy resolve(String path) {
    for (final _PolicyRule rule in _rules) {
      if (rule.matches(path)) {
        return rule.policy;
      }
    }
    return _defaultPolicy;
  }

  /// 清空全部规则，保留默认策略。
  void clear() => _rules.clear();
}

/// 单条匹配规则。
final class _PolicyRule {
  const _PolicyRule({required this.pattern, required this.policy});

  final RegExp pattern;
  final CachePolicy policy;

  bool matches(String path) => pattern.hasMatch(path);
}
