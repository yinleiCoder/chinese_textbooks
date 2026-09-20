import 'dart:async';
import 'dart:collection';

/// 请求闸门：同时约束**并发上限**与**最小发起间隔**。
///
/// 为什么两件事要放在一个类里：它们是同一个资源（服务端配额）的两面。
/// 分开实现会出现"并发确实只有 3，但 3 个请求在同一毫秒发出"的空隙——
/// 而平台恰恰是对瞬时突发最敏感的（实测会回 400）。
///
/// 平台要求（来自参考项目的实测值）：并发 ≤3、相邻请求间隔 ≥200ms。
final class RequestGate {
  RequestGate({
    required this.maxConcurrent,
    required this.minInterval,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 并发上限。
  final int maxConcurrent;

  /// 相邻两次放行之间的最小间隔。
  final Duration minInterval;

  /// 可注入的时钟，让"1 秒内最多发起几次"这类断言可以确定性地验证。
  final DateTime Function() _clock;

  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  int _running = 0;
  DateTime? _lastReleaseAt;
  bool _pumping = false;

  /// 当前占用中的槽位数。
  int get runningCount => _running;

  /// 等待中的请求数。
  int get waitingCount => _waiting.length;

  /// 取得一个放行许可。
  ///
  /// 返回的 Future 完成时才真正可以发请求。**必须在 finally 里调用
  /// [release]**，否则槽位会永久泄漏，后续请求全部卡死。
  Future<void> acquire() {
    if (_running < maxConcurrent && _waiting.isEmpty) {
      _running++;
      return _waitForInterval();
    }
    final Completer<void> completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  /// 归还许可并唤醒下一个等待者。
  void release() {
    _lastReleaseAt = _clock();
    _running--;
    _pump();
  }

  /// 派发等待队列。
  void _pump() {
    if (_pumping) {
      return;
    }
    _pumping = true;
    try {
      while (_running < maxConcurrent && _waiting.isNotEmpty) {
        _running++;
        final Completer<void> next = _waiting.removeFirst();
        unawaited(_waitForInterval().then((_) => next.complete()));
      }
    } finally {
      _pumping = false;
    }
  }

  /// 补足与上一次放行之间的时间差。
  ///
  /// 注意 `_lastReleaseAt` 在这里更新而不是在 [release] 里：间隔约束的是
  /// **发起时刻**，而 release 可能远晚于发起（大文件下完才释放）。
  Future<void> _waitForInterval() async {
    final DateTime? last = _lastReleaseAt;
    if (last != null) {
      final Duration elapsed = _clock().difference(last);
      if (elapsed < minInterval) {
        await Future<void>.delayed(minInterval - elapsed);
      }
    }
    _lastReleaseAt = _clock();
  }
}
