import 'dart:io';

import 'package:dio/dio.dart';

import '../services/catalog/catalog.dart';
import '../services/http/http.dart';
import '../services/logger/app_logger.dart';
import '../utils/utils.dart';
import '../values/values.dart';
import 'api_client.dart';
import 'nd_endpoints.dart';

/// 教材目录相关接口。
///
/// 实现 [CatalogDownloader]，因此仓储层完全不知道 dio 的存在——
/// 增量更新、失败回滚这些真正容易出错的逻辑可以脱离网络单测。
final class CatalogApi implements CatalogDownloader {
  CatalogApi({
    required this._apiClient,
    required this._failureMapper,
    required this._logger,
  });

  final ApiClient _apiClient;
  final FailureMapper _failureMapper;
  final AppLogger _logger;

  /// 拉取版本探针。
  ///
  /// **刻意不给这个接口注册缓存策略。** 它是 1KB 的版本探针，
  /// 走缓存会让"平台上有更新"这件事被 `cacheFirst` 藏起来——
  /// 而它本来就是用来发现更新的。
  @override
  Future<Result<CatalogVersionInfo>> fetchVersion() async {
    final Result<Map<String, dynamic>> result = await _apiClient
        .get<Map<String, dynamic>>(
          NdEndpoints.dataVersion.toString(),
          decoder: ApiClient.raw<Map<String, dynamic>>(
            (Object? data) => data! as Map<String, dynamic>,
          ),
        );

    return result.map((Map<String, dynamic> json) {
      final Object? urls = json['urls'];
      final List<Uri> partUrls = <Uri>[
        if (urls is String)
          for (final String raw in urls.split(','))
            if (raw.trim().isNotEmpty) NdEndpoints.resolvePartUrl(raw),
      ];
      final Object? moduleVersion = json['module_version'];
      return CatalogVersionInfo(
        partUrls: partUrls,
        moduleVersion: moduleVersion is int ? moduleVersion : null,
      );
    });
  }

  /// 下载单个分片。
  @override
  Future<Result<DownloadOutcome>> downloadPart(
    Uri url,
    File target, {
    String? etag,
    PartProgressCallback? onProgress,
  }) => _downloadToFile(url, target, etag: etag, onProgress: onProgress);

  /// 下载标签树。
  @override
  Future<Result<DownloadOutcome>> downloadTagTree(
    File target, {
    String? etag,
  }) => _downloadToFile(NdEndpoints.tagTree, target, etag: etag);

  // ==================== 内部实现 ====================

  Future<Result<DownloadOutcome>> _downloadToFile(
    Uri url,
    File target, {
    String? etag,
    PartProgressCallback? onProgress,
  }) async {
    // 先下到临时文件，成功后再原子替换。
    //
    // **这一步不能省。** dio 的 `download` 会在检查状态码之前就把目标文件
    // 打开并截断，304 时同样如此——直接下到正式路径的话，一次增量探测就会
    // 把本地的 `tags.json` 清成空文件，用户下次启动看到"没有目录数据"，
    // 而清单与分片都还在，表现成莫名其妙的重新下载。这个坑真的踩过。
    final File temp = File('${target.path}.part');

    try {
      await target.parent.create(recursive: true);
      if (temp.existsSync()) {
        await temp.delete();
      }

      final Response<dynamic> response = await _apiClient.dio.download(
        url.toString(),
        temp.path,
        options: Options(
          headers: <String, dynamic>{
            // 条件请求：内容没变时服务端回 304，省掉一次 10MB 传输。
            // `?etag` 是空值感知的映射项：值为 null 时整条不写入。
            HttpHeaders.ifNoneMatchHeader: ?etag,
            // 若服务端启用了 gzip，落盘的是解压后字节而 Content-Length
            // 报的是压缩后大小，长度校验会假阳性失败。显式声明不做内容编码。
            HttpHeaders.acceptEncodingHeader: 'identity',
          },
          // 10MB 的分片在移动网络下远超默认的 20 秒接收超时。
          receiveTimeout: NdConfig.partDownloadTimeout,
          // 304 不是错误，交给下面按状态码分支处理。
          validateStatus: _acceptOkOrNotModified,
        ),
        onReceiveProgress: onProgress,
        // 中途失败时删掉半截文件，避免它被当成完整数据。
        deleteOnError: true,
      );

      if (response.statusCode == HttpStatus.notModified) {
        // 本地内容仍然有效，正式文件始终没被碰过，丢掉临时文件即可。
        if (temp.existsSync()) {
          await temp.delete();
        }
        return const Success<DownloadOutcome>(DownloadOutcome.notModified());
      }

      // Windows 上 rename 到已存在的路径会失败，必须先删目标。
      if (target.existsSync()) {
        await target.delete();
      }
      await temp.rename(target.path);

      return Success<DownloadOutcome>(
        DownloadOutcome.downloaded(
          response.headers.value(HttpHeaders.etagHeader),
        ),
      );
    } on DioException catch (error, stackTrace) {
      if (temp.existsSync()) {
        await temp.delete();
      }
      _logger.w('下载失败：${url.path}', error, stackTrace);
      return Failure<DownloadOutcome>(_failureMapper.map(error));
    } on Object catch (error, stackTrace) {
      if (temp.existsSync()) {
        await temp.delete();
      }
      // 落盘失败（磁盘满、路径不可写）不是网络问题，单独归类。
      _logger.e('写入目录数据失败：${target.path}', error, stackTrace);
      return Failure<DownloadOutcome>(
        CacheFailure(message: '写入目录数据失败', cause: error, stackTrace: stackTrace),
      );
    }
  }

  static bool _acceptOkOrNotModified(int? status) =>
      status != null &&
      ((status >= 200 && status < 300) || status == HttpStatus.notModified);
}
