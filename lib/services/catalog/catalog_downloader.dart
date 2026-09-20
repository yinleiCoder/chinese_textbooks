import 'dart:io';

import '../../utils/utils.dart';

/// 版本探针的结果。
final class CatalogVersionInfo {
  const CatalogVersionInfo({required this.partUrls, this.moduleVersion});

  /// 各分片的下载地址。
  final List<Uri> partUrls;

  /// 平台给出的 `module_version`。
  ///
  /// 只作诊断记录。**不能用来判断内容是否更新**——实测它停在 2023-03-19，
  /// 而分片内容更新到 2026-09，两者毫无关系。判断更新看 ETag。
  final int? moduleVersion;
}

/// 一次下载的结果。
final class DownloadOutcome {
  /// 服务端返回 304，本地内容仍然有效。
  const DownloadOutcome.notModified() : etag = null, changed = false;

  /// 下载到了新内容。
  const DownloadOutcome.downloaded(this.etag) : changed = true;

  /// 响应头里的 ETag，供下次做条件请求。
  final String? etag;

  /// 内容是否发生了变化。
  final bool changed;
}

/// 分片下载的进度回调：(已接收字节, 总字节或 0)。
typedef PartProgressCallback = void Function(int received, int total);

/// 目录数据的下载能力。
///
/// 抽成接口是为了让仓储层**不依赖 dio**，从而可以用一个假实现做纯 Dart 单测——
/// 增量更新、失败回滚、分片合并这些逻辑才是真正容易出错的地方，
/// 而它们完全不需要真实网络就能验证。
abstract interface class CatalogDownloader {
  /// 拉取版本探针，得到分片地址列表。
  Future<Result<CatalogVersionInfo>> fetchVersion();

  /// 下载单个分片。
  ///
  /// [etag] 非空时发起条件请求，服务端回 304 则返回
  /// [DownloadOutcome.notModified]，不会写 [target]。
  Future<Result<DownloadOutcome>> downloadPart(
    Uri url,
    File target, {
    String? etag,
    PartProgressCallback? onProgress,
  });

  /// 下载标签树。
  Future<Result<DownloadOutcome>> downloadTagTree(File target, {String? etag});
}
