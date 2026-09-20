import 'dart:async';

import 'package:flutter/foundation.dart';

import '../apis/apis.dart';
import '../entity/entity.dart';
import '../services/download/download_manager.dart';
import '../services/logger/app_logger.dart';
import '../utils/utils.dart';

/// 下载队列在界面侧的投影。
///
/// ## 职责边界
///
/// 服务层（`DownloadManager`）只用 `dart:io` + dio，不碰 Flutter；
/// 这一层只做三件事：订阅事件流、把事件转成 `notifyListeners`、
/// 以及把"勾选的教材"翻译成"下载任务"。
///
/// ## 通知合并
///
/// 三个并发任务同时推进时，进度事件可以到每秒几十条。逐条 notify 会让
/// 整个下载页每秒重建几十次。这里收到事件只置脏标记，并用一个 100ms 的
/// 定时器合并成一次通知。
final class DownloadProvider extends ChangeNotifier {
  DownloadProvider({
    required this._manager,
    required this._textbookApi,
    required this._logger,
    required this._isAlreadyDownloaded,
  }) {
    _subscription = _manager.events.listen(_onEvent);
  }

  final DownloadManager _manager;
  final TextbookApi _textbookApi;
  final AppLogger _logger;

  /// 判断某本是否已在本地。
  ///
  /// 用回调而不是直接依赖 `LibraryProvider`：状态层之间不该互相引用，
  /// 由组合根把两者接起来即可。
  final bool Function(String textbookId) _isAlreadyDownloaded;

  late final StreamSubscription<DownloadEvent> _subscription;
  Timer? _flushTimer;
  bool _dirty = false;
  bool _resolving = false;
  int _resolvedCount = 0;
  int _resolveTotal = 0;

  /// 当前任务列表。
  List<DownloadTask> get tasks => _manager.tasks;

  /// 是否正在解析选中教材的下载地址。
  bool get isResolving => _resolving;

  /// 解析进度，用于"正在解析 3/12"。
  int get resolvedCount => _resolvedCount;
  int get resolveTotal => _resolveTotal;

  /// 是否有未完成的任务。
  bool get hasActive => tasks.any((DownloadTask t) => !t.isTerminal);

  /// 教材是否已下载完成。
  bool isDownloaded(String textbookId) => _manager.isDownloaded(textbookId);

  /// 已下载完成的教材 id。
  Set<String> get completedIds => _manager.completedIds;

  /// 把选中的教材加入下载队列。
  ///
  /// 下载需要 PDF 地址与文件大小，而这两样只有详情接口有——清单里
  /// `ti_items` 是空数组。所以入队前必须**逐本解析详情**，这一步是串行的：
  /// 并发解析会瞬间打出十几个请求，而平台对突发很敏感。
  Future<void> enqueue(List<Textbook> books) async {
    if (_resolving || books.isEmpty) {
      return;
    }
    _resolving = true;
    _resolvedCount = 0;
    _resolveTotal = books.length;
    notifyListeners();

    final List<DownloadTask> ready = <DownloadTask>[];
    for (final Textbook book in books) {
      _resolvedCount++;
      notifyListeners();

      // 先看磁盘再看任务表：已下载过的书不该被重复下载，
      // 而"已下载"这件事在一次会话结束后只剩磁盘记得。
      if (_isAlreadyDownloaded(book.id) || _manager.isDownloaded(book.id)) {
        continue;
      }
      final Result<TextbookDetail> result = await _textbookApi.fetchDetail(
        book.id,
      );
      switch (result) {
        case Success<TextbookDetail>(:final TextbookDetail data):
          if (!data.isDownloadable) {
            _logger.w('跳过（没有源文件）：${book.title}');
            continue;
          }
          ready.add(
            DownloadTask(
              textbookId: book.id,
              title: book.title,
              mirrors: data.pdfMirrors,
              expectedBytes: data.sizeBytes ?? 0,
              pageCount: data.pageCount,
            ),
          );
        case Failure<TextbookDetail>(:final AppFailure failure):
          _logger.w('解析失败（${failure.message}）：${book.title}');
      }
    }

    _resolving = false;
    notifyListeners();

    if (ready.isNotEmpty) {
      _manager.enqueue(ready);
    }
  }

  /// 取消任务。
  void cancel(String textbookId) => _manager.cancel(textbookId);

  /// 重试任务。
  void retry(String textbookId) => _manager.retry(textbookId);

  /// 重试全部失败任务。
  void retryAllFailed() => _manager.retryAllFailed();

  /// 清空已完成记录。
  void clearCompleted() => _manager.clearCompleted();

  @override
  void dispose() {
    _flushTimer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  // ==================== 内部实现 ====================

  void _onEvent(DownloadEvent event) {
    _dirty = true;
    _flushTimer ??= Timer(const Duration(milliseconds: 100), _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (!_dirty) {
      return;
    }
    _dirty = false;
    notifyListeners();
  }
}
