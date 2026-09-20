import 'dart:io';
import 'dart:isolate';

import '../../utils/utils.dart';
import '../logger/app_logger.dart';
import 'catalog_downloader.dart';
import 'catalog_file_store.dart';
import 'catalog_index.dart';
import 'catalog_manifest.dart';
import 'catalog_part_parser.dart';
import 'catalog_progress.dart';
import 'catalog_snapshot_codec.dart';

/// 目录仓储：把"平台上的教材清单"变成"内存里可查询的索引"。
///
/// 分成三个明确的能力，调用方按场景选：
/// - [loadLocal]：**不碰网络**，只读本地。冷启动走它，先让界面可用；
/// - [refreshIfNeeded]：后台探测更新，没有变化就什么都不做；
/// - [forceRefresh]：用户在设置页点"重新下载目录"。
///
/// 更新粒度是**分片级**的：某个分片的 ETag 没变就原样复用本地解析结果，
/// 只有变化的分片重新下载与解析。平台每次更新通常只动一两个分片，
/// 这让日常更新从"重下 40MB"变成"几百 KB"。
final class CatalogRepository {
  const CatalogRepository({
    required this._downloader,
    required this._fileStore,
    required this._logger,
  });

  final CatalogDownloader _downloader;
  final CatalogFileStore _fileStore;
  final AppLogger _logger;

  /// 只读本地，不发起任何网络请求。
  ///
  /// 失败通常意味着"首次安装"或"缓存被清理"，调用方应引导用户下载目录数据。
  Future<Result<CatalogIndex>> loadLocal() async {
    try {
      final CatalogManifest? manifest = await _fileStore.readManifest();
      if (manifest == null) {
        return const Failure<CatalogIndex>(CacheFailure(message: '尚未下载教材目录'));
      }
      if (!_fileStore.tagTreeFile.existsSync()) {
        return const Failure<CatalogIndex>(CacheFailure(message: '教材目录数据不完整'));
      }

      final List<String> shardPaths = <String>[];
      for (final String fileName in manifest.shardFileNames) {
        final File file = _fileStore.shardFile(fileName);
        if (file.existsSync()) {
          shardPaths.add(file.path);
        }
      }
      if (shardPaths.isEmpty) {
        return const Failure<CatalogIndex>(CacheFailure(message: '教材目录数据不完整'));
      }

      final CatalogIndex index = await CatalogIndex.buildInBackground(
        shardPaths: shardPaths,
        tagTreePath: _fileStore.tagTreeFile.path,
      );
      // 解出 0 本说明缓存已经读不懂了（格式升版、文件损坏）。
      // 必须当作失败上报，否则界面会显示一个空目录，而不是引导用户
      // 重新下载——前者看起来像"平台没有教材"。
      if (index.isEmpty) {
        _logger.w('本地目录为空，判定为缓存失效');
        return const Failure<CatalogIndex>(
          CacheFailure(message: '本地教材目录已失效，需要重新下载'),
        );
      }

      _logger.i('本地目录已载入，共 ${index.length} 本教材');
      return Success<CatalogIndex>(index);
    } on Object catch (error, stackTrace) {
      _logger.e('载入本地目录失败', error, stackTrace);
      return Failure<CatalogIndex>(
        CacheFailure(
          message: '读取本地教材目录失败',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 探测并应用更新。
  ///
  /// 返回 `null` 表示**版本未变**，调用方应当继续使用手里的索引，
  /// 不要重新渲染整个目录。
  Future<Result<CatalogIndex?>> refreshIfNeeded({
    CatalogProgressCallback? onProgress,
  }) => _refresh(force: false, onProgress: onProgress);

  /// 强制重新拉取全部分片。
  Future<Result<CatalogIndex?>> forceRefresh({
    CatalogProgressCallback? onProgress,
  }) => _refresh(force: true, onProgress: onProgress);

  /// 删除全部本地目录数据。
  Future<void> clear() => _fileStore.deleteAll();

  /// 目录数据占用的磁盘空间。
  Future<int> usageBytes() => _fileStore.usageBytes();

  // ==================== 内部实现 ====================

  Future<Result<CatalogIndex?>> _refresh({
    required bool force,
    CatalogProgressCallback? onProgress,
  }) async {
    try {
      onProgress?.call(const CatalogProgress(stage: CatalogStage.checking));

      final Result<CatalogVersionInfo> versionResult = await _downloader
          .fetchVersion();
      if (versionResult case Failure<CatalogVersionInfo>(
        :final AppFailure failure,
      )) {
        onProgress?.call(const CatalogProgress(stage: CatalogStage.failed));
        return Failure<CatalogIndex?>(failure);
      }
      final CatalogVersionInfo version =
          (versionResult as Success<CatalogVersionInfo>).data;
      if (version.partUrls.isEmpty) {
        onProgress?.call(const CatalogProgress(stage: CatalogStage.failed));
        return const Failure<CatalogIndex?>(
          ServerFailure(message: '平台返回的教材目录为空'),
        );
      }

      final CatalogManifest? oldManifest = await _fileStore.readManifest();
      final Map<String, CatalogPartEntry> oldParts = <String, CatalogPartEntry>{
        for (final CatalogPartEntry part
            in oldManifest?.parts ?? const <CatalogPartEntry>[])
          part.url: part,
      };

      // 本地分片解不出来（例如格式版本升过级）时必须重下。
      // 不做这个判断的话，ETag 全都对得上、`changed` 永远是 false，
      // 而缓存又读不懂——表现为"目录永远是空的"，且怎么点更新都没用。
      final bool localUsable = await _isLocalUsable(oldManifest);

      await _fileStore.clearStaging();
      await _fileStore.shardDirectory.create(recursive: true);

      final int total = version.partUrls.length;
      bool changed = false;
      int completed = 0;
      final List<CatalogPartEntry> newParts = <CatalogPartEntry>[];

      onProgress?.call(
        CatalogProgress(stage: CatalogStage.downloading, totalParts: total),
      );

      for (final Uri url in version.partUrls) {
        final String fileName = _fileStore.shardFileNameFor(url);
        final File shardFile = _fileStore.shardFile(fileName);
        final CatalogPartEntry? old = oldParts[url.toString()];

        final bool canReuse =
            localUsable &&
            !force &&
            old != null &&
            old.fileName == fileName &&
            old.etag != null &&
            shardFile.existsSync();

        final Result<DownloadOutcome> outcome = await _downloadShard(
          url: url,
          fileName: fileName,
          etag: canReuse ? old.etag : null,
          onProgress: onProgress,
          completedParts: completed,
          totalParts: total,
        );

        if (outcome case Failure<DownloadOutcome>(:final AppFailure failure)) {
          onProgress?.call(const CatalogProgress(stage: CatalogStage.failed));
          return Failure<CatalogIndex?>(failure);
        }
        final DownloadOutcome result =
            (outcome as Success<DownloadOutcome>).data;

        if (result.changed) {
          changed = true;
          newParts.add(
            CatalogPartEntry(
              url: url.toString(),
              fileName: fileName,
              count: await _countRows(shardFile),
              etag: result.etag,
            ),
          );
        } else {
          // 304：本地解析结果仍然有效，直接复用。
          newParts.add(
            CatalogPartEntry(
              url: url.toString(),
              fileName: fileName,
              count: old?.count ?? await _countRows(shardFile),
              etag: old?.etag,
            ),
          );
        }

        completed++;
        onProgress?.call(
          CatalogProgress(
            stage: CatalogStage.downloading,
            completedParts: completed,
            totalParts: total,
          ),
        );
      }

      // ---------- 标签树 ----------
      final ({bool changed, String? etag}) tagResult = await _refreshTagTree(
        force: force,
        oldManifest: oldManifest,
        onProgress: onProgress,
      );
      changed = changed || tagResult.changed;

      // 没有变化就到此为止：不写清单、不重建索引，调用方继续用旧索引。
      if (!changed) {
        _logger.i('教材目录已是最新，跳过更新');
        onProgress?.call(CatalogProgress.ready);
        return const Success<CatalogIndex?>(null);
      }

      // ---------- 提交 ----------
      // 清单最后写：它是"本次可用"的凭据，只有前面全部落盘成功它才会更新。
      final CatalogManifest manifest = CatalogManifest(
        fetchedAt: DateTime.now(),
        parts: newParts,
        tagEtag: tagResult.etag,
        moduleVersion: version.moduleVersion,
      );
      await _fileStore.writeManifest(manifest);
      await _fileStore.pruneShards(newParts.map((p) => p.fileName).toSet());

      // ---------- 建索引 ----------
      onProgress?.call(const CatalogProgress(stage: CatalogStage.indexing));
      final CatalogIndex index = await CatalogIndex.buildInBackground(
        shardPaths: newParts
            .map(
              (CatalogPartEntry part) =>
                  _fileStore.shardFile(part.fileName).path,
            )
            .toList(growable: false),
        tagTreePath: _fileStore.tagTreeFile.path,
      );

      _logger.i('教材目录已更新，共 ${index.length} 本教材');
      onProgress?.call(CatalogProgress.ready);
      return Success<CatalogIndex?>(index);
    } on Object catch (error, stackTrace) {
      _logger.e('更新教材目录失败', error, stackTrace);
      onProgress?.call(const CatalogProgress(stage: CatalogStage.failed));
      return Failure<CatalogIndex?>(
        CacheFailure(message: '更新教材目录失败', cause: error, stackTrace: stackTrace),
      );
    }
  }

  /// 本地缓存是否仍然可读。
  ///
  /// 抽查第一个分片就够：格式版本是全局的，一个读不出来就都读不出来。
  Future<bool> _isLocalUsable(CatalogManifest? manifest) async {
    final List<CatalogPartEntry> parts =
        manifest?.parts ?? const <CatalogPartEntry>[];
    if (parts.isEmpty) {
      return true;
    }
    final File file = _fileStore.shardFile(parts.first.fileName);
    if (!file.existsSync()) {
      return false;
    }
    return CatalogShardCodec.decode(await file.readAsString()) != null;
  }

  /// 下载并解析单个分片。
  Future<Result<DownloadOutcome>> _downloadShard({
    required Uri url,
    required String fileName,
    required String? etag,
    required CatalogProgressCallback? onProgress,
    required int completedParts,
    required int totalParts,
  }) async {
    final File staging = File(
      '${_fileStore.stagingDirectory.path}${Platform.pathSeparator}$fileName',
    );

    final Result<DownloadOutcome> outcome = await _downloader.downloadPart(
      url,
      staging,
      etag: etag,
      onProgress: (int received, int total) => onProgress?.call(
        CatalogProgress(
          stage: CatalogStage.downloading,
          completedParts: completedParts,
          totalParts: totalParts,
          receivedBytes: received,
          totalBytes: total > 0 ? total : null,
        ),
      ),
    );

    if (outcome case Failure<DownloadOutcome>()) {
      return outcome;
    }
    if (!(outcome as Success<DownloadOutcome>).data.changed) {
      return outcome;
    }

    // 解析放在后台 isolate：单个分片约 10MB，解码后的中间对象可达上百 MB，
    // 留在主 isolate 上会造成肉眼可见的卡顿。
    onProgress?.call(
      CatalogProgress(
        stage: CatalogStage.parsing,
        completedParts: completedParts,
        totalParts: totalParts,
      ),
    );
    final List<List<String>> rows = await _parsePartInBackground(staging.path);
    await _fileStore.writeShard(fileName, CatalogShardCodec.encode(rows));
    return outcome;
  }

  /// 刷新标签树。
  ///
  /// 标签树拿不到时**不算整体失败**：分片是好的就仍然能建出目录树，
  /// 只是分类名会回落到 tag_id。让用户看到目录，比因为一个 200KB 的文件
  /// 失败而整块不可用要好。
  Future<({bool changed, String? etag})> _refreshTagTree({
    required bool force,
    required CatalogManifest? oldManifest,
    required CatalogProgressCallback? onProgress,
  }) async {
    final File target = _fileStore.tagTreeFile;
    final bool exists = target.existsSync();
    onProgress?.call(const CatalogProgress(stage: CatalogStage.parsing));

    final Result<DownloadOutcome> result = await _downloader.downloadTagTree(
      target,
      etag: force || !exists ? null : oldManifest?.tagEtag,
    );
    if (result case Failure<DownloadOutcome>()) {
      return (changed: false, etag: oldManifest?.tagEtag);
    }
    final DownloadOutcome outcome = (result as Success<DownloadOutcome>).data;
    return (
      changed: outcome.changed,
      // 未变化时 outcome.etag 必然是 null（304 不返回新 ETag），
      // 此时沿用旧值，避免下次退化成无条件请求。
      etag: outcome.etag ?? oldManifest?.tagEtag,
    );
  }

  /// 统计某个分片文件里的条目数。
  Future<int> _countRows(File shardFile) async {
    if (!shardFile.existsSync()) {
      return 0;
    }
    final List<List<String>>? rows = CatalogShardCodec.decode(
      await shardFile.readAsString(),
    );
    return rows?.length ?? 0;
  }
}

/// 在后台 isolate 中解析一个分片文件。
///
/// **必须是顶层函数，不能在实例方法里直接写 `Isolate.run(() => ...)`
/// 再捕获局部变量。** 实例方法里的闭包会连带捕获 `this`，而 `this` 持有
/// `AppLogger`（内含 `Logger` 尚未完成的 `Future`）——这类对象不能跨 isolate
/// 传递，运行时抛 `object is unsendable`，而**编译期完全看不出来**。
///
/// 这个坑是靠 `tool/verify_catalog_test.dart` 对着真实数据跑出来的：
/// 所有单测都是绿的，界面也能正常显示，只有在真正解析 10MB 分片时才炸。
Future<List<List<String>>> _parsePartInBackground(String path) =>
    Isolate.run(() => parseCatalogPart(path));
