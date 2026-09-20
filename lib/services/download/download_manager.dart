import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../entity/entity.dart';
import '../../values/values.dart';
import '../logger/app_logger.dart';
import '../storage/app_paths.dart';
import 'mirror_planner.dart';
import 'request_gate.dart';

/// 下载事件。
final class DownloadEvent {
  const DownloadEvent(this.task);

  final DownloadTask task;
}

/// 下载队列。
///
/// ## 服务层，不依赖 Flutter
///
/// 只用 `dart:io` + dio + logger，因此可以脱离 widget 树单测；
/// 通知界面的事交给 `DownloadProvider`。
///
/// ## 两条硬性限流约束
///
/// 全部下载都必须过 [RequestGate]：并发 ≤3、相邻请求间隔 ≥200ms。
/// 这是平台最敏感的环节，参考项目实测"短时间连打会回 400"。
///
/// ## 与参考项目对齐的三处细节
///
/// 1. **400 同址退避重试，不换镜像**——400 多半是突发限流，立刻改打 r2/r3
///    只会把限流打得更死；
/// 2. **401/403 立即放弃**——三个私有镜像共享同一套鉴权，换也过不了；
/// 3. **`.part` 下完再原子重命名**——中途失败不会留下半截文件冒充成品。
final class DownloadManager {
  DownloadManager({
    required this._client,
    required this._paths,
    required this._logger,
    required this._isLoggedIn,
    this.planner = const MirrorPlanner(),
    this.maxConcurrent = NdConfig.downloadConcurrency,
    this.minInterval = NdConfig.minRequestInterval,
  }) : _gate = RequestGate(
         maxConcurrent: maxConcurrent,
         minInterval: minInterval,
       );

  final Dio _client;
  final AppPaths _paths;
  final AppLogger _logger;

  /// 登录态查询。
  ///
  /// 用回调而不是快照：用户可能在下载过程中登录，之后的任务应当走私有域。
  final bool Function() _isLoggedIn;

  final MirrorPlanner planner;
  final int maxConcurrent;
  final Duration minInterval;

  final RequestGate _gate;
  final StreamController<DownloadEvent> _events =
      StreamController<DownloadEvent>.broadcast();
  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  final List<String> _queue = <String>[];
  bool _disposed = false;

  /// 任务变化流。
  Stream<DownloadEvent> get events => _events.stream;

  /// 当前全部任务，按入队顺序。
  List<DownloadTask> get tasks =>
      List<DownloadTask>.unmodifiable(_tasks.values);

  /// 按教材 id 取任务。
  DownloadTask? taskOf(String textbookId) => _tasks[textbookId];

  /// 已下载完成的教材 id。
  Set<String> get completedIds => <String>{
    for (final DownloadTask task in _tasks.values)
      if (task.status == DownloadStatus.completed) task.textbookId,
  };

  /// 教材是否已下载完成。
  bool isDownloaded(String textbookId) =>
      _tasks[textbookId]?.status == DownloadStatus.completed;

  /// 入队。
  ///
  /// 幂等：同一本已在队列中或已完成时跳过，避免用户连点造成重复任务。
  void enqueue(Iterable<DownloadTask> incoming) {
    bool added = false;
    for (final DownloadTask task in incoming) {
      final DownloadTask? existing = _tasks[task.textbookId];
      if (existing != null && !existing.isTerminal) {
        continue;
      }
      if (existing?.status == DownloadStatus.completed) {
        continue;
      }
      _tasks[task.textbookId] = task;
      _queue.add(task.textbookId);
      added = true;
    }
    if (added) {
      _emitAll();
      _pump();
    }
  }

  /// 取消一个任务。
  void cancel(String textbookId) {
    _tokens[textbookId]?.cancel('用户取消');
    _queue.remove(textbookId);
    _update(taskOf(textbookId)?.cancelled());
  }

  /// 重试一个失败或取消的任务。
  void retry(String textbookId) {
    final DownloadTask? task = _tasks[textbookId];
    if (task == null || !task.canRetry) {
      return;
    }
    _tasks[textbookId] = task.requeued();
    if (!_queue.contains(textbookId)) {
      _queue.add(textbookId);
    }
    _emitAll();
    _pump();
  }

  /// 重试全部失败任务。
  void retryAllFailed() {
    for (final DownloadTask task in tasks) {
      if (task.status == DownloadStatus.failed && task.canRetry) {
        retry(task.textbookId);
      }
    }
  }

  /// 清空已完成的任务记录。
  void clearCompleted() {
    _tasks.removeWhere(
      (String _, DownloadTask task) => task.status == DownloadStatus.completed,
    );
    _emitAll();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final CancelToken token in _tokens.values) {
      token.cancel('应用退出');
    }
    _tokens.clear();
    await _events.close();
  }

  // ==================== 调度 ====================

  /// 有空位就取任务启动。
  void _pump() {
    if (_disposed) {
      return;
    }
    while (_queue.isNotEmpty && _gate.runningCount < maxConcurrent) {
      final String id = _queue.removeAt(0);
      final DownloadTask? task = _tasks[id];
      if (task == null || task.isTerminal) {
        continue;
      }
      unawaited(_run(task));
    }
  }

  /// 执行一个任务。
  ///
  /// 这是本类最长的一段，仍然留在类里而不是拆成 `DownloadWorker`：
  /// 它需要 gate、镜像策略、落盘、状态回写四样东西，拆出去后这些都得
  /// 通过构造参数传一遍，反而更难读。等它再长出分支（断点续传、多文件）
  /// 时再拆。
  Future<void> _run(DownloadTask task) async {
    await _gate.acquire();
    final CancelToken token = CancelToken();
    _tokens[task.textbookId] = token;

    final Stopwatch watch = Stopwatch()..start();

    // **状态必须沿着"最新的那一份"推进。** `task` 是入队时的原始对象，
    // 状态还是 queued；如果每次都用它去派生，`progressed()` 会因为
    // "状态不是 running"直接原样返回，`_update` 又把这个 queued 对象
    // 写回去——进度全丢、状态被覆盖，最后一步才跳到 completed。
    DownloadTask current = _update(task.started())!;

    try {
      final List<Uri> candidates = planner.plan(task, loggedIn: _isLoggedIn());
      if (candidates.isEmpty) {
        _update(current.failed(DownloadFailureReason.notFound, '没有可用的下载地址'));
        return;
      }

      final Directory tmp = _paths.tmp;
      final File target = File(
        '${_paths.pdfDirectory.path}${Platform.pathSeparator}${task.textbookId}.pdf',
      );
      await _paths.pdfDirectory.create(recursive: true);

      Object? lastError;
      for (final Uri url in candidates) {
        final _AttemptResult result = await _attempt(
          task: current,
          url: url,
          tmpDirectory: tmp,
          target: target,
          token: token,
          watch: watch,
          // 进度回调把"最新状态"送回 _run，由它推进局部变量——
          // 状态只能沿着最新的一份往前走，理由见上面的注释。
          onProgress: (DownloadTask latest) =>
              current = _update(latest) ?? current,
        );
        switch (result) {
          case _AttemptSuccess():
            _update(current.succeeded(target.path));
            watch.stop();
            // 把速度记下来。"下载慢"这件事必须能定位到是平台带宽、
            // 网络链路还是我们自己的实现——没有数字就只能猜。
            final double seconds = watch.elapsedMilliseconds / 1000;
            final double mb = current.expectedBytes / 1024 / 1024;
            _logger.i(
              '下载完成：${current.title}'
              '（${mb.toStringAsFixed(1)}MB / '
              '${seconds.toStringAsFixed(1)}s = '
              '${(seconds <= 0 ? 0 : mb / seconds).toStringAsFixed(2)}MB/s）',
            );
            return;
          case _AttemptAuthRequired():
            _update(
              current.withRequiresAuth().failed(
                DownloadFailureReason.authRequired,
                '该教材需要登录后下载',
              ),
            );
            // 三个私有镜像共享鉴权，继续试只是白撞配额。
            return;
          case _AttemptFailed(:final String message):
            lastError = message;
        }
      }

      _update(
        current.failed(
          DownloadFailureReason.mirrorExhausted,
          '所有下载地址都失败了${lastError == null ? '' : '：$lastError'}',
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger.e('下载异常：${current.title}', error, stackTrace);
      _update(current.failed(DownloadFailureReason.unknown, '下载失败：$error'));
    } finally {
      _tokens.remove(task.textbookId);
      _gate.release();
      _pump();
    }
  }

  /// 尝试一个地址。
  Future<_AttemptResult> _attempt({
    required DownloadTask task,
    required Uri url,
    required Directory tmpDirectory,
    required File target,
    required CancelToken token,
    required DownloadTask Function(DownloadTask task) onProgress,
    required Stopwatch watch,
  }) async {
    final File temp = File(
      '${tmpDirectory.path}${Platform.pathSeparator}${task.textbookId}.part',
    );

    for (int retry = 0; ; retry++) {
      try {
        if (temp.existsSync()) {
          await temp.delete();
        }
        final Response<dynamic> response = await _client.download(
          url.toString(),
          temp.path,
          cancelToken: token,
          options: Options(
            // 若服务端启用了 gzip，落盘的是解压后字节而 Content-Length
            // 报的是压缩后大小，长度校验会假阳性失败。
            headers: <String, dynamic>{
              HttpHeaders.acceptEncodingHeader: 'identity',
            },
            receiveTimeout: NdConfig.partDownloadTimeout,
          ),
          onReceiveProgress: (int received, int total) {
            // 平均速度而不是瞬时速度：瞬时值在分块边界上抖动得厉害，
            // 界面上跳来跳去反而看不清。
            final int elapsedMs = watch.elapsedMilliseconds;
            final int speed = elapsedMs <= 0
                ? 0
                : (received * 1000 / elapsedMs).round();
            onProgress(task.progressed(received, bytesPerSecond: speed));
          },
          deleteOnError: true,
        );

        if (response.statusCode != HttpStatus.ok) {
          return _AttemptFailed('HTTP ${response.statusCode}');
        }

        // 完整性校验：字节数与平台给出的 ti_size 不符就是坏的。
        final int expected = task.expectedBytes;
        if (expected > 0) {
          final int actual = await temp.length();
          if (actual != expected) {
            await temp.delete();
            return _AttemptFailed('文件不完整（$actual/$expected 字节）');
          }
        }

        // Windows 上 rename 到已存在的路径会失败，必须先删目标。
        if (target.existsSync()) {
          await target.delete();
        }
        await temp.rename(target.path);
        return const _AttemptSuccess();
      } on DioException catch (error) {
        final int? status = error.response?.statusCode;
        if (status == HttpStatus.unauthorized ||
            status == HttpStatus.forbidden) {
          // 公开镜像 403 是正常的（它只覆盖约 30%），换下一个候选；
          // 私有镜像 401/403 才是凭据问题，交给上层终止整个任务。
          if (MirrorPlanner.isPrivate(url)) {
            return const _AttemptAuthRequired();
          }
          return _AttemptFailed('HTTP $status');
        }
        if (status == HttpStatus.badRequest &&
            retry < NdConfig.rateLimitBackoff.length) {
          // 400 是限流：**同址**退避重试，不换镜像。
          final Duration delay = NdConfig.rateLimitBackoff[retry];
          _logger.w('被限流，${delay.inMilliseconds}ms 后重试同一地址');
          await Future<void>.delayed(delay);
          continue;
        }
        if (CancelToken.isCancel(error)) {
          return const _AttemptFailed('已取消');
        }
        return _AttemptFailed(error.message ?? '网络错误');
      } on Object catch (error) {
        if (temp.existsSync()) {
          await temp.delete();
        }
        return _AttemptFailed('$error');
      }
    }
  }

  // ==================== 状态回写 ====================

  /// 节流后的进度上报。
  ///
  /// 一个 40MB 的文件会产生上千次进度回调，全部透传出去会让界面每秒重建
  /// 上百次。只在**变化超过 1%**时才发事件。
  DownloadTask? _update(DownloadTask? task) {
    if (task == null || _disposed) {
      return task;
    }
    final DownloadTask? previous = _tasks[task.textbookId];
    _tasks[task.textbookId] = task;
    // 进度节流：一个 40MB 的文件会产生上千次回调，只有变化超过 1%
    // 才值得通知界面。
    if (previous != null &&
        previous.status == task.status &&
        previous.expectedBytes > 0 &&
        (task.receivedBytes - previous.receivedBytes).abs() * 100 <
            previous.expectedBytes) {
      return task;
    }
    if (!_events.isClosed) {
      _events.add(DownloadEvent(task));
    }
    return task;
  }

  /// 队列结构变化（入队 / 重试 / 清理），需要整表刷新。
  void _emitAll() {
    if (_disposed || _events.isClosed) {
      return;
    }
    for (final DownloadTask task in _tasks.values) {
      _events.add(DownloadEvent(task));
    }
  }
}

/// 单次尝试的结果。
sealed class _AttemptResult {
  const _AttemptResult();
}

final class _AttemptSuccess extends _AttemptResult {
  const _AttemptSuccess();
}

/// 私有域拒绝了凭据——需要登录，继续试别的镜像没有意义。
final class _AttemptAuthRequired extends _AttemptResult {
  const _AttemptAuthRequired();
}

final class _AttemptFailed extends _AttemptResult {
  const _AttemptFailed(this.message);

  final String message;
}
