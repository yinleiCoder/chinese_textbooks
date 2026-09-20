import 'dart:async';

/// 防抖器：连续触发时只执行**最后一次**。
///
/// 典型场景是搜索框输入——用户每敲一个字都发请求既浪费流量也浪费服务端资源，
/// 这里等用户停顿 [delay] 之后再发。
///
/// ```dart
/// final _debouncer = Debouncer();
///
/// void onQueryChanged(String keyword) => _debouncer.run(() => search(keyword));
///
/// @override
/// void dispose() {
///   _debouncer.dispose();
///   super.dispose();
/// }
/// ```
///
/// 注意：[Debouncer] 持有 [Timer]，必须在 `State.dispose` 中调用 [dispose]，
/// 否则可能在页面销毁后仍触发回调。
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  /// 触发后等待的静默时长。
  final Duration delay;

  Timer? _timer;
  void Function()? _pending;

  /// 是否有等待中的任务。
  bool get isPending => _timer?.isActive ?? false;

  /// 提交一次调用，取消此前尚未触发的任务。
  void run(void Function() action) {
    _timer?.cancel();
    _pending = action;
    _timer = Timer(delay, () {
      _pending = null;
      action();
    });
  }

  /// 立即执行等待中的任务，若没有则什么也不做。
  ///
  /// 用于"用户直接点了提交按钮，不必再等防抖"的场景。
  void flush() {
    final void Function()? pending = _pending;
    if (pending == null) {
      return;
    }
    cancel();
    pending();
  }

  /// 取消等待中的任务，不执行。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  /// 释放资源。
  void dispose() => cancel();
}

/// 节流器：在 [interval] 内最多执行**一次**。
///
/// 与 [Debouncer] 的区别是它会**立即**执行第一次调用，
/// 适合滚动回调、按钮连点拦截这类需要即时反馈的场景。
class Throttler {
  Throttler({this.interval = const Duration(milliseconds: 500)});

  /// 两次执行之间的最小间隔。
  final Duration interval;

  DateTime? _lastRunAt;

  /// 若已过冷却期则立即执行 [action] 并返回 `true`，否则丢弃并返回 `false`。
  bool run(void Function() action) {
    final DateTime now = DateTime.now();
    final DateTime? lastRunAt = _lastRunAt;
    if (lastRunAt != null && now.difference(lastRunAt) < interval) {
      return false;
    }
    _lastRunAt = now;
    action();
    return true;
  }

  /// 重置冷却状态，使下一次调用必定执行。
  void reset() => _lastRunAt = null;
}
