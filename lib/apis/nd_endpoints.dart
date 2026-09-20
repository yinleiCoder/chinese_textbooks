import '../values/values.dart';

/// 智慧教育平台的接口地址。
///
/// **平台接口一旦调整，只需要改这一个文件。** 参考项目的历史 issue 表明
/// 这类平台接口平均每年会变几次，把路径拼装收敛在这里，
/// 是为了让"接口挂了"从"翻遍代码找 URL"变成"改一处"。
abstract final class NdEndpoints {
  /// 版本探针（约 1KB）。
  static Uri get dataVersion =>
      Uri.parse('${NdConfig.jsonHost}${NdConfig.dataVersionPath}');

  /// 教材分类树（约 200KB）。
  static Uri get tagTree =>
      Uri.parse('${NdConfig.jsonHost}${NdConfig.tagTreePath}');

  /// 教材详情。
  static Uri textbookDetail(String contentId) => Uri.parse(
    '${NdConfig.jsonHost}${NdConfig.textbookDetailPath(contentId)}',
  );

  /// 电子教材的章节目录树。
  static Uri ebookTree(String ebookId) =>
      Uri.parse('${NdConfig.jsonHost}${NdConfig.ebookTreePath(ebookId)}');

  /// 把分片地址规范成绝对 URL。
  ///
  /// 平台目前给的是绝对地址，但没有契约保证——一旦改成相对路径，
  /// 直接 `Uri.parse` 会得到一个缺 host 的 URI，请求会打到一个空主机上，
  /// 错误信息还很难看出根因。这里以 [dataVersion] 为基准兜住这种情况。
  static Uri resolvePartUrl(String raw) {
    final String trimmed = raw.trim();
    final Uri parsed = Uri.parse(trimmed);
    return parsed.hasScheme ? parsed : dataVersion.resolve(trimmed);
  }

  /// 由私有地址推出**公开镜像**地址（去掉主机名里的 `-private`）。
  ///
  /// 公开镜像不需要任何凭据，但实测只覆盖约 30% 的教材，
  /// 因此它只是"未登录时的碰运气路径"，不能当作主路径。
  /// 主机名不含 `-private` 时返回 `null`。
  static Uri? publicMirrorOf(Uri privateUrl) {
    final String host = privateUrl.host;
    if (!host.contains('-ndr-private.')) {
      return null;
    }
    return privateUrl.replace(
      host: host.replaceFirst('-ndr-private.', '-ndr.'),
    );
  }

  /// 列出某个私有地址的全部镜像，**原地址优先**。
  ///
  /// 三个私有镜像路径完全相同，只有域名不同。非私有地址原样返回。
  static List<Uri> privateMirrors(Uri url) {
    if (!NdConfig.privateHosts.contains(url.host)) {
      return <Uri>[url];
    }
    return <Uri>[
      url,
      for (final String host in NdConfig.privateHosts)
        if (host != url.host) url.replace(host: host),
    ];
  }

  /// 列出某个私有地址的全部公开镜像。
  ///
  /// 非私有地址返回空列表。
  static List<Uri> publicMirrors(Uri url) {
    if (!NdConfig.privateHosts.contains(url.host)) {
      return const <Uri>[];
    }
    return <Uri>[
      for (final String host in NdConfig.publicHosts) url.replace(host: host),
    ];
  }
}
