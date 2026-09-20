import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/catalog/catalog.dart';
import '../services/logger/app_logger.dart';
import '../utils/utils.dart';

/// 目录的加载状态。
enum CatalogStatus {
  /// 尚未开始。
  idle,

  /// 正在读取本地数据或下载。
  loading,

  /// 已就绪，可以浏览。
  ready,

  /// 本地没有目录数据，需要先下载（首次安装或缓存被清理）。
  needsDownload,

  /// 失败。
  failed,
}

/// 教材目录状态。
///
/// 启动策略是**先本地、后网络**：先用手里的数据把界面点亮，
/// 再在后台探测更新。用户不必盯着一个空白页等 40MB 下载完。
///
/// 目录数据只在这里持有一份。它同时被目录树、书架、下载等多处使用，
/// 属于典型的跨页面共享状态，因此放在 `providers/` 而不是某个页面里。
final class CatalogProvider extends ChangeNotifier {
  CatalogProvider({required this._repository, required this._logger});

  final CatalogRepository _repository;
  final AppLogger _logger;

  CatalogStatus _status = CatalogStatus.idle;
  CatalogIndex? _index;
  CatalogProgress _progress = CatalogProgress.idle;
  AppFailure? _failure;
  bool _refreshing = false;

  /// 当前状态。
  CatalogStatus get status => _status;

  /// 目录索引，未就绪时为 `null`。
  CatalogIndex? get index => _index;

  /// 加载进度。
  CatalogProgress get progress => _progress;

  /// 失败详情。
  AppFailure? get failure => _failure;

  /// 是否已有可用数据（即使正在后台更新）。
  bool get hasData => _index != null;

  /// 教材总数。
  int get bookCount => _index?.length ?? 0;

  /// 启动时调用一次。
  ///
  /// 幂等：重复调用不会重复加载。
  Future<void> initialize() async {
    if (_status != CatalogStatus.idle) {
      return;
    }
    _status = CatalogStatus.loading;
    notifyListeners();

    final Result<CatalogIndex> local = await _repository.loadLocal();
    switch (local) {
      case Success<CatalogIndex>(:final CatalogIndex data):
        _index = data;
        _status = CatalogStatus.ready;
        notifyListeners();
        // 后台探测更新，不阻塞首屏。
        unawaited(_refreshInBackground());
      case Failure<CatalogIndex>(:final AppFailure failure):
        _logger.i('本地没有教材目录：${failure.message}');
        _failure = failure;
        _status = CatalogStatus.needsDownload;
        notifyListeners();
    }
  }

  /// 下载（或重新下载）目录数据。
  ///
  /// 首次安装时走这条路；更新失败需要重试时也走它。
  Future<void> download() async {
    if (_status == CatalogStatus.loading) {
      return;
    }
    _status = CatalogStatus.loading;
    _failure = null;
    _progress = const CatalogProgress(stage: CatalogStage.checking);
    notifyListeners();

    final Result<CatalogIndex?> result = await _repository.refreshIfNeeded(
      onProgress: _onProgress,
    );
    _applyRefreshResult(result);
  }

  /// 强制重新拉取全部分片（设置页的"重新下载目录"）。
  Future<void> forceRefresh() async {
    if (_status == CatalogStatus.loading) {
      return;
    }
    _status = CatalogStatus.loading;
    _failure = null;
    _progress = const CatalogProgress(stage: CatalogStage.checking);
    notifyListeners();

    final Result<CatalogIndex?> result = await _repository.forceRefresh(
      onProgress: _onProgress,
    );
    _applyRefreshResult(result);
  }

  /// 删除本地目录数据。
  Future<void> clearLocal() async {
    await _repository.clear();
    _index = null;
    _status = CatalogStatus.needsDownload;
    _progress = CatalogProgress.idle;
    notifyListeners();
  }

  /// 目录数据占用的磁盘空间。
  Future<int> diskUsageBytes() => _repository.usageBytes();

  // ==================== 内部实现 ====================

  /// 后台探测更新。
  ///
  /// 失败**不改变界面状态**：用户手里的数据仍然可用，
  /// 为一个后台请求弹错误提示只会造成困扰。日志里有记录就够了。
  Future<void> _refreshInBackground() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final Result<CatalogIndex?> result = await _repository.refreshIfNeeded(
        onProgress: _onProgress,
      );
      switch (result) {
        case Success<CatalogIndex?>(:final CatalogIndex? data):
          // null 表示版本未变，什么都不用做。
          if (data != null) {
            _index = data;
            _logger.i('教材目录已在后台更新，共 ${data.length} 本');
            notifyListeners();
          }
        case Failure<CatalogIndex?>():
          // 静默失败，见方法注释。
          break;
      }
    } finally {
      _refreshing = false;
    }
  }

  void _applyRefreshResult(Result<CatalogIndex?> result) {
    switch (result) {
      case Success<CatalogIndex?>(:final CatalogIndex? data):
        if (data != null) {
          _index = data;
        }
        _status = _index == null
            ? CatalogStatus.needsDownload
            : CatalogStatus.ready;
      case Failure<CatalogIndex?>(:final AppFailure failure):
        _failure = failure;
        // 已有数据时不要因为一次更新失败就把界面打成错误态。
        _status = _index == null ? CatalogStatus.failed : CatalogStatus.ready;
    }
    notifyListeners();
  }

  void _onProgress(CatalogProgress progress) {
    _progress = progress;
    notifyListeners();
  }
}
