/// 国家中小学智慧教育平台（ND = National platform for smart eDucation）的接口常量。
///
/// **平台接口一旦调整，只需要改这一个文件。** 参考项目的历史 issue 表明
/// 这类平台接口平均每年会变几次，把域名、路径、请求头、限流参数全部收敛在这里，
/// 是为了让"接口挂了"这件事从"翻遍代码找 URL"变成"改一行"。
///
/// 各项取值的来源：
/// - 主机与路径：`https://docs` 无，实测 + 站点生产包 `app-*.js` 中提取；
/// - 限流与重试参数：参考项目 `ui/download_panel.py` 的实测值；
/// - 签名格式：参考项目 `auth.py` 对官网 UC SDK 的还原。
abstract final class NdConfig {
  // ==================== 主机 ====================

  /// 平台站点首页，登录页从这里进入。
  static const String siteHome = 'https://basic.smartedu.cn/';

  /// JSON 接口主机（目录、详情、标签树）。完全公开，无需任何凭据。
  static const String jsonHost = 'https://s-file-1.ykt.cbern.com.cn';

  /// JSON 接口备用主机。与 [jsonHost] 内容一致，实测互为镜像。
  static const String jsonHostMirror = 'https://s-file-2.ykt.cbern.com.cn';

  /// 私有 CDN 主机，**必须携带 `X-ND-AUTH` 签名**，否则 GET 返回 401。
  ///
  /// 三个镜像路径完全相同，仅域名不同；下载时按此顺序轮换。
  static const List<String> privateHosts = <String>[
    'r1-ndr-private.ykt.cbern.com.cn',
    'r2-ndr-private.ykt.cbern.com.cn',
    'r3-ndr-private.ykt.cbern.com.cn',
  ];

  /// 公开镜像主机：把私有主机名去掉 `-private`。
  ///
  /// **不需要任何凭据**，但实测只覆盖约 30% 的教材（随机抽样 10 本命中 3 本）。
  /// 因此它只是"未登录时的碰运气路径"，不能当作主路径。
  static const List<String> publicHosts = <String>[
    'r1-ndr.ykt.cbern.com.cn',
    'r2-ndr.ykt.cbern.com.cn',
    'r3-ndr.ykt.cbern.com.cn',
  ];

  // ==================== 分类维度 ====================

  /// tag 维度 id → 中文名。
  ///
  /// 两个用途：给筛选栏的分组起标题；决定分组在界面上的**排列顺序**。
  ///
  /// 注意这只是**展示顺序**，不是层级定义。平台的标签树各分支深度并不一致
  /// （有的分类缺版本层、有的缺册次层），所以筛选按维度匹配、不按层号对齐，
  /// 详见 `CatalogFilter` 的注释。这里的顺序取自实测的典型层级。
  static const Map<String, String> tagDimensionLabels = <String, String>{
    'zxxxd': '学段',
    'zxxxk': '学科',
    'zxxbb': '版本',
    'zxxnj': '年级',
    'zxxcc': '册次',
    // 特殊教育的学校类型（盲校 / 聋校 / 培智学校）。
    'zxxlb': '类别',
  };

  /// 推断不出维度时，层级标题回落到这个前缀 + 层号。
  static const String unknownDimensionPrefix = '分类';

  // ==================== 路径 ====================

  /// 目录版本探针。
  ///
  /// 响应 `{"module":"tch_material","module_version":1679266141,"urls":"..."}`。
  ///
  /// ⚠️ **`module_version` 不可用于判断内容是否更新**：实测它停在 2023-03-19，
  /// 而分片内容的 `update_time` 最新到 2026-09-15。判断更新一律用分片 ETag。
  static const String dataVersionPath =
      '/zxx/ndrs/resources/tch_material/version/data_version.json';

  /// 教材分类树（tag_id → 中文名）。
  static const String tagTreePath = '/zxx/ndrs/tags/tch_material_tag.json';

  /// 教材详情。
  static String textbookDetailPath(String contentId) =>
      '/zxx/ndrv2/resources/tch_material/details/$contentId.json';

  /// 电子教材的章节目录树（由 `ebook_mapping` 里的 `ebook_id` 索引）。
  static String ebookTreePath(String ebookId) =>
      '/zxx/ndrv2/national_lesson/trees/$ebookId.json';

  // ==================== 请求头 ====================

  /// 签名请求头名。
  static const String ndAuthHeader = 'X-ND-AUTH';

  /// CDN 会校验来源，必须带。
  static const String origin = 'https://basic.smartedu.cn';

  /// CDN 会校验来源，必须带（注意结尾的斜杠）。
  static const String referer = 'https://basic.smartedu.cn/';

  /// 站点前端的 User-Agent。
  ///
  /// 用浏览器 UA 而不是 `Dart/3.x (dart:io)`：后者会被 CDN 当作非预期客户端。
  /// 这里沿用参考项目实测可用的形式，只把平台标识改成 Windows（本应用的主力平台）。
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 匿名请求的 Authorization 头。
  ///
  /// 站点前端固定发这个形式，`0` 表示匿名。**它不是真实凭据**，
  /// 真正的鉴权走 [ndAuthHeader]。
  static const String anonymousAuthorization = 'Bearer 0';

  /// 未登录时使用的占位签名头。
  ///
  /// 对公开 JSON 接口无害（那些接口根本不校验），对私有 PDF 会得到 401。
  static const String placeholderNdAuth = 'MAC id="0",nonce="0",mac="0"';

  // ==================== 限流 ====================

  /// 同时占用私有 CDN 的最大任务数。
  ///
  /// 参考项目实测：短时间连打会返回 400，因此必须限制并发。
  static const int downloadConcurrency = 3;

  /// 相邻两次私有 CDN 请求的最小间隔。
  ///
  /// 与 [downloadConcurrency] 是两个不同维度的约束，必须同时生效——
  /// 只限并发会出现"3 个请求在同一毫秒发出"的空隙。
  static const Duration minRequestInterval = Duration(milliseconds: 200);

  /// 收到 400 时的同址退避时长。
  ///
  /// **不要改成换镜像**：400 多半是突发限流，连打 r2/r3 只会把限流打得更死；
  /// 同址稍等、用新的 nonce 重新签名即可。
  static const List<Duration> rateLimitBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  // ==================== 分块下载 ====================

  /// 小于 [chunkMediumThreshold] 的文件使用的分块大小。
  static const int chunkSmall = 128 * 1024;

  /// 中等大小文件的分块。
  static const int chunkMedium = 256 * 1024;

  /// 大文件的分块。
  static const int chunkLarge = 512 * 1024;

  /// 中等分块的阈值：20MB。
  static const int chunkMediumThreshold = 20 * 1024 * 1024;

  /// 大分块的阈值：50MB。
  static const int chunkLargeThreshold = 50 * 1024 * 1024;

  // ==================== 签名 ====================

  /// nonce 随机后缀的字符表。
  ///
  /// ⚠️ 官网实现的下标是 `ceil(35 * random())`——**是 35 不是 36**，
  /// 所以 `'0'` 几乎抽不到。这是照抄官网的行为，不要"顺手修正"成 36。
  static const String nonceAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// nonce 随机后缀的长度。
  static const int nonceSuffixLength = 8;

  /// 签名头里 [nonceAlphabet] 取下标时用的上界。
  static const int nonceIndexBound = 35;

  // ==================== 本地目录名 ====================

  /// 目录数据的根目录名。
  static const String catalogDirName = 'catalog';

  /// 已下载教材的根目录名。
  static const String libraryDirName = 'library';

  /// 下载中间文件的目录名。
  ///
  /// **必须与 [libraryDirName] 在同一卷下**，否则 `File.rename` 会退化成
  /// 跨卷复制，原子性丢失。
  static const String tmpDirName = 'tmp';

  // ==================== 其他 ====================

  /// 资源就绪后仍需要的额外等待，用于规避 CDN 的短时热点。
  static const Duration requestTimeout = Duration(seconds: 60);

  /// 目录分片的下载超时（10MB，需要比普通请求宽松）。
  static const Duration partDownloadTimeout = Duration(minutes: 3);
}
