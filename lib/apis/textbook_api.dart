import '../entity/entity.dart';
import '../services/logger/app_logger.dart';
import '../utils/utils.dart';
import '../values/values.dart';
import 'api_client.dart';
import 'nd_endpoints.dart';

/// 教材详情接口。
///
/// 清单里拿不到任何文件地址（`ti_items` 是空数组），必须逐本请求详情。
/// 详情返回的 `ti_items` 里每个元素是一种"表示形式"，需要挑出真正的源文件。
final class TextbookApi {
  const TextbookApi({required this._apiClient, required this._logger});

  final ApiClient _apiClient;
  final AppLogger _logger;

  /// 说明该教材**只有子资源、没有独立详情**的业务错误码。
  static const String detailUnavailableCode = 'detailUnavailable';

  /// 取教材详情。
  Future<Result<TextbookDetail>> fetchDetail(String contentId) async {
    final Result<Map<String, dynamic>> raw = await _apiClient
        .get<Map<String, dynamic>>(
          NdEndpoints.textbookDetail(contentId).toString(),
          decoder: ApiClient.raw<Map<String, dynamic>>(
            (Object? data) => data! as Map<String, dynamic>,
          ),
        );

    return switch (raw) {
      Success<Map<String, dynamic>>(:final Map<String, dynamic> data) => _parse(
        contentId,
        data,
      ),
      Failure<Map<String, dynamic>>(:final AppFailure failure) =>
        Failure<TextbookDetail>(_rewrite(failure)),
    };
  }

  /// 把失败重新归类。
  ///
  /// **详情接口在公开主机上，403 与登录状态无关。** 实测有一部分教材在清单里
  /// 存在，但详情接口对它返回 403——这类条目只有子资源，没有独立详情。
  /// 若不改写，`FailureMapper` 会把 403 映射成 `AuthFailure`，界面就会显示
  /// "没有访问权限"，用户会以为是账号问题。
  AppFailure _rewrite(AppFailure failure) {
    if (failure is! AuthFailure) {
      return failure;
    }
    _logger.i('该教材没有独立详情（${failure.typeName}）');
    return BusinessFailure(
      code: detailUnavailableCode,
      message: AppStrings.detailUnavailable,
      cause: failure.cause,
      stackTrace: failure.stackTrace,
    );
  }

  /// 从详情 JSON 提取需要的信息。
  Result<TextbookDetail> _parse(String contentId, Map<String, dynamic> json) {
    final Object? items = json['ti_items'];
    if (items is! List) {
      return const Failure<TextbookDetail>(
        ParseFailure(message: AppStrings.errorParse, cause: '缺少 ti_items'),
      );
    }

    final Map<String, dynamic>? source = _findSourceItem(items);
    if (source == null) {
      // 详情拿到了，但里面没有源文件——同样是"只有子资源"的情况。
      return const Failure<TextbookDetail>(
        BusinessFailure(
          code: detailUnavailableCode,
          message: AppStrings.detailUnavailable,
        ),
      );
    }

    return Success<TextbookDetail>(
      TextbookDetail(
        contentId: contentId,
        title: _titleOf(json),
        pdfMirrors: _extractMirrors(source),
        sizeBytes: _intOf(source['ti_size']),
        pageCount: _pageCountOf(source),
        previewUrl: _extractPreview(json, items),
        ebookMappingUrl: _extractEbookMappingUrl(items),
      ),
    );
  }

  /// 找源文件项——**两轮查找**，与参考项目 `api.py` 的策略一致。
  ///
  /// 第一轮认 `ti_is_source_file`，它是最可靠的判据；没命中再按
  /// `ti_file_flag` 兜底，因为实测个别条目漏标了前者。
  /// 两轮都跳过 `ti_format == "folder"`——那是逐页图片，不是可下载的单个文件。
  static Map<String, dynamic>? _findSourceItem(List<Object?> items) {
    for (final Object? item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      if (item['ti_is_source_file'] != true) {
        continue;
      }
      if (item['ti_format'] == 'folder') {
        continue;
      }
      return item;
    }

    const Set<String> fallbackFlags = <String>{
      'source',
      'pdf',
      'ppt',
      'pptx',
      'doc',
      'docx',
    };
    for (final Object? item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      if (!fallbackFlags.contains(item['ti_file_flag'])) {
        continue;
      }
      if (item['ti_format'] == 'folder') {
        continue;
      }
      return item;
    }
    return null;
  }

  /// 取镜像地址。
  ///
  /// 优先 `ti_storages`——它直接给出 r1/r2/r3 三个完整地址，保留全部三个
  /// 供下载器轮换。参考项目只取第一个，白丢了两份容错。
  /// 它为空时再退回 `ti_storage` 模板，把 `cs_path:${ref-path}` 换成主机名。
  static List<Uri> _extractMirrors(Map<String, dynamic> item) {
    final Object? storages = item['ti_storages'];
    if (storages is List) {
      final List<Uri> uris = <Uri>[
        for (final Object? url in storages)
          if (url is String && url.isNotEmpty) Uri.parse(url),
      ];
      if (uris.isNotEmpty) {
        return uris;
      }
    }

    final Object? template = item['ti_storage'];
    if (template is String && template.isNotEmpty) {
      return <Uri>[
        Uri.parse(
          template.replaceFirst(
            r'cs_path:${ref-path}',
            'https://${NdConfig.privateHosts.first}',
          ),
        ),
      ];
    }
    return const <Uri>[];
  }

  /// 取总页数。
  ///
  /// 来自 `custom_properties.requirements[]` 里 `name == "pagesize"` 的项。
  /// **不要拿预览图数量推算**——预览集通常只有几十张，而教材有上百页。
  static int? _pageCountOf(Map<String, dynamic> item) {
    final Object? custom = item['custom_properties'];
    if (custom is! Map<String, dynamic>) {
      return null;
    }
    final Object? requirements = custom['requirements'];
    if (requirements is! List) {
      return null;
    }
    for (final Object? requirement in requirements) {
      if (requirement is! Map<String, dynamic>) {
        continue;
      }
      if (requirement['name'] == 'pagesize') {
        final Object? value = requirement['value'];
        return value is String ? int.tryParse(value) : _intOf(value);
      }
    }
    return null;
  }

  /// 找章节映射文件的地址。
  ///
  /// 本期只做整册下载，这个地址是为二期的"按章节下载"预留：
  /// 下载该 txt 得到 `{ebook_id, mappings}`，再用 `ebook_id` 请求章节树。
  static String? _extractEbookMappingUrl(List<Object?> items) {
    for (final Object? item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      if (item['ti_file_flag'] != 'ebook_mapping') {
        continue;
      }
      final List<Uri> mirrors = _extractMirrors(item);
      if (mirrors.isNotEmpty) {
        return mirrors.first.toString();
      }
    }
    return null;
  }

  /// 取封面。
  ///
  /// 优先 `custom_properties.thumbnails`（第 1 页，就是封面）；
  /// 它缺失时退回 `thumbnail_1` 条目，再退回 `preview` 里页码最小的那张。
  static String? _extractPreview(
    Map<String, dynamic> json,
    List<Object?> items,
  ) {
    final Object? custom = json['custom_properties'];
    if (custom is Map<String, dynamic>) {
      final String? cover = pickCoverUrl(
        thumbnails: custom['thumbnails'],
        preview: custom['preview'],
      );
      if (cover != null) {
        return cover;
      }
    }
    for (final Object? item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final Object? flag = item['ti_file_flag'];
      if (flag != 'thumbnail_1' && flag != 'thumbnail') {
        continue;
      }
      final List<Uri> mirrors = _extractMirrors(item);
      if (mirrors.isNotEmpty) {
        return mirrors.first.toString();
      }
    }
    return null;
  }

  /// 取标题，优先中文本地化字段。
  static String _titleOf(Map<String, dynamic> json) {
    final Object? globalTitle = json['global_title'];
    if (globalTitle is Map<String, dynamic>) {
      final Object? zh = globalTitle['zh-CN'];
      if (zh is String && zh.isNotEmpty) {
        return zh;
      }
    }
    final Object? title = json['title'];
    return title is String ? title : '';
  }

  static int? _intOf(Object? value) => value is int ? value : null;
}
