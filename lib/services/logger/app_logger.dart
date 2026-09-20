import 'package:logger/logger.dart';

/// 统一日志出口。
///
/// 设计要点：
/// - 全局禁止直接使用 `print`（`avoid_print` 已开启），所有输出走这里，
///   便于按环境调整级别、以及后续接入日志上报；
/// - 级别策略由构造参数 `verbose` 决定，而不是散落各处的 `kDebugMode` 判断；
/// - 通过构造函数注入使用方（拦截器、仓储、Provider），而不是静态单例，
///   这样单元测试里可以传入静默实现。
final class AppLogger {
  /// 创建日志器。
  ///
  /// [verbose] 为 `true` 时输出 trace 及以上（开发 / 预发），
  /// 为 `false` 时只输出 warning 及以上（生产）。
  AppLogger({required bool verbose})
    : _logger = Logger(
        filter: verbose ? DevelopmentFilter() : ProductionFilter(),
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: verbose ? 8 : 0,
          lineLength: 100,
          colors: verbose,
          printEmojis: true,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        ),
        level: verbose ? Level.trace : Level.warning,
      );

  final Logger _logger;

  /// 底层 [Logger] 实例，供需要自定义 printer 的场景使用。
  Logger get raw => _logger;

  /// trace：最细粒度的执行轨迹，仅开发期使用。
  void t(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.t(message, error: error, stackTrace: stackTrace);

  /// debug：调试信息，例如请求参数、缓存命中情况。
  void d(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.d(message, error: error, stackTrace: stackTrace);

  /// info：正常但值得记录的关键流程节点。
  void i(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.i(message, error: error, stackTrace: stackTrace);

  /// warning：可恢复的异常，例如缓存写入失败、接口降级。
  void w(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.w(message, error: error, stackTrace: stackTrace);

  /// error：影响功能的异常。
  void e(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  /// fatal：导致应用不可用的严重错误。
  void f(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.f(message, error: error, stackTrace: stackTrace);

  /// 记录一次耗时操作。
  ///
  /// 返回被包裹的 [action] 的执行结果，耗时以 debug 级别输出。
  Future<T> trace<T>(String label, Future<T> Function() action) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      d('$label 耗时 ${stopwatch.elapsedMilliseconds}ms');
    }
  }
}
