/// 应用文案。
///
/// 当前产品只面向中文用户，文案集中在此便于统一校对；
/// 若后续需要多语言，把这里的常量迁移到 `.arb` 资源即可，
/// 调用方（`AppStrings.xxx`）的写法保持不变。
abstract final class AppStrings {
  // ==================== 通用 ====================

  /// 重试。
  static const String retry = '重试';

  /// 取消。
  static const String cancel = '取消';

  /// 确定。
  static const String confirm = '确定';

  /// 保存。
  static const String save = '保存';

  /// 删除。
  static const String delete = '删除';

  /// 刷新。
  static const String refresh = '刷新';

  /// 加载中。
  static const String loading = '加载中…';

  /// 暂无数据。
  static const String empty = '暂无数据';

  /// 空数据时的补充说明。
  static const String emptyHint = '换个条件试试，或稍后再来看看';

  /// 未知。
  static const String unknown = '未知';

  // ==================== 错误提示 ====================

  /// 网络不可用。
  static const String errorNetwork = '网络连接不可用，请检查网络后重试';

  /// 请求超时。
  static const String errorTimeout = '请求超时，请稍后重试';

  /// 服务器异常。
  static const String errorServer = '服务器开小差了，请稍后重试';

  /// 请求参数有误。
  static const String errorClient = '请求有误，请稍后重试';

  /// 登录态失效。
  static const String errorUnauthorized = '登录状态已过期，请重新登录';

  /// 无权限。
  static const String errorForbidden = '没有访问权限';

  /// 数据解析失败。
  static const String errorParse = '数据格式异常，请升级应用后重试';

  /// 缓存异常。
  static const String errorCache = '本地数据读取失败';

  /// 兜底错误。
  static const String errorUnknown = '出了点问题，请稍后重试';

  // ==================== 页面标题 ====================

  /// 欢迎页标题。
  static const String welcomeTitle = '语文教材';

  /// 欢迎页副标题。
  static const String welcomeSubtitle = '让每一篇课文都有迹可循';

  /// 页面不存在。
  static const String pageNotFound = '页面不存在';

  /// 页面不存在的补充说明。
  static const String pageNotFoundHint = '该页面可能已被移除，返回首页继续浏览';

  /// 返回首页。
  static const String backToHome = '返回首页';

  // ==================== 阅读器 ====================

  /// 阅读器标题（未从书架进入时）。
  static const String readerTitle = '阅读';

  /// 文件缺失。
  static const String readerFileMissing = '找不到这本教材的文件';

  /// 文件缺失说明。
  static const String readerFileMissingHint = '它可能已被删除，去目录里重新下载即可';

  /// 继续阅读。
  static const String readerContinue = '继续阅读';

  /// 从第 N 页继续。
  static String readerContinueFrom(int page) => '读到第 $page 页';

  /// 封面上的页码角标，如「P12」。
  static String readerPageBadge(int page) => 'P$page';

  /// 登录页初始化提示。
  ///
  /// 内置浏览器在 Windows 上首次创建要加载 WebView2 运行时，实测要十几秒。
  /// 不提示的话用户会以为页面坏了。
  static const String loginInitializing = '正在初始化内置浏览器，首次打开可能需要十几秒…';

  /// 导出。
  static const String readerExport = '导出到…';

  /// 导出成功。
  static String readerExported(String location) => '已导出到 $location';

  /// 导出失败。
  static const String readerExportFailed = '导出已取消或失败';

  /// 删除本地文件。
  static const String readerRemove = '删除本地文件';

  /// 删除确认。
  static const String readerRemoveConfirm = '删除后需要重新下载。确定删除？';

  // ==================== 下载队列 ====================

  /// 正在解析下载地址。
  static const String downloadResolving = '正在解析下载地址';

  /// 排队中。
  static const String downloadQueued = '排队中';

  /// 下载中。
  static const String downloadRunning = '下载中';

  /// 失败。
  static const String downloadFailed = '失败';

  /// 已取消。
  static const String downloadCancelled = '已取消';

  /// 重试全部失败。
  static String downloadRetryAllFailed(int count) => '重试失败（$count）';

  /// 清空已完成。
  static const String downloadClearCompleted = '清空已完成';

  /// 队列概览，如「已完成 2/12」。
  static String downloadSummary(int done, int total) => '已完成 $done/$total';

  // ==================== 设置 ====================

  /// 外观设置。
  static const String themeTitle = '外观';

  /// 跟随系统。
  static const String themeSystem = '跟随系统';

  /// 浅色模式。
  static const String themeLight = '浅色';

  /// 深色模式。
  static const String themeDark = '深色';

  /// 语言设置。
  static const String localeTitle = '语言';

  /// 简体中文。
  static const String localeChinese = '简体中文';

  /// 英文。
  static const String localeEnglish = 'English';

  // ==================== 教材目录 ====================

  /// 目录准备页标题（首次）。
  static const String catalogSetupTitle = '准备教材目录';

  /// 首次下载的说明。
  static const String catalogSetupHint =
      '首次使用需要下载教材目录数据（约 40 MB）。\n'
      '下载一次之后可以离线浏览全部教材，之后只会增量更新变化的部分。';

  /// 目录更新页标题。
  static const String catalogRefreshTitle = '更新教材目录';

  /// 更新的说明。
  static const String catalogRefreshHint =
      '重新下载教材目录数据。\n'
      '平台每次通常只更新其中一部分，这里会只重下变化的分片。';

  /// 下载按钮。
  static const String catalogDownloadAction = '开始下载';

  /// 下载期间的提示。
  static const String catalogSetupKeepOpen = '请保持应用在前台，完成后自动进入';

  /// 阶段：探测版本。
  static const String catalogStageChecking = '正在检查更新…';

  /// 阶段：下载。
  static const String catalogStageDownloading = '正在下载教材目录';

  /// 阶段：解析。
  static const String catalogStageParsing = '正在解析数据…';

  /// 阶段：建索引。
  static const String catalogStageIndexing = '正在整理目录…';

  /// 阶段：完成。
  static const String catalogStageReady = '准备完成';

  /// 目录更新完成。
  static String catalogUpdated(int count) => '教材目录已更新，共 $count 本';

  /// 目录准备完成。
  static const String catalogReady = '教材目录已准备好';

  /// 目录条目数，如「共 3565 本教材」。
  static String catalogBookCount(int count) => '共 $count 本教材';

  // ==================== 导航 ====================

  /// 书架。
  static const String tabLibrary = '书架';

  /// 目录。
  static const String tabBrowse = '目录';

  /// 下载。
  static const String tabDownloads = '下载';

  /// 设置。
  static const String tabSettings = '设置';

  // ==================== 目录页 ====================

  /// 搜索框占位。
  static const String searchHint = '搜索书名、学科、版本…';

  /// 展开。
  static const String expand = '展开';

  /// 收起。
  static const String collapse = '收起';

  /// 展开全部。
  static const String expandAll = '展开全部';

  /// 收起全部。
  static const String collapseAll = '收起全部';

  /// 筛选栏里"更多"按钮。
  static const String filterMore = '更多';

  /// 清空全部筛选。
  static const String clearFilters = '清空筛选';

  /// 尚未设置任何筛选条件时的提示。
  static const String clearFiltersHint = '未设置筛选条件';

  /// 筛选面板标题。
  static const String filterTitle = '筛选';

  /// 清空单个维度。
  static const String clearDimension = '清空';

  /// 全选当前结果。
  static const String selectAllResults = '全选结果';

  /// 清空勾选。
  static const String clearSelection = '清空勾选';

  /// 下载选中。
  static const String downloadSelected = '下载选中';

  /// 下载尚未接入时的占位提示。
  static const String downloadNotWired = '下载队列将在下一阶段接入';

  /// 查看下载队列。
  static const String downloadView = '查看';

  /// 目录数据未就绪时的提示。
  static const String downloadNeedCatalog = '教材目录还没准备好，请稍后再试';

  /// 已加入下载队列。
  static String downloadEnqueued(int count) => '已将 $count 本加入下载队列';

  /// 已选数量，如「已选 12 本」。
  static String selectedCount(int count) => '已选 $count 本';

  /// 结果数量，如「共 189 本」。
  static String resultCount(int count) => '共 $count 本';

  /// 筛选无结果标题。
  static const String noResultTitle = '没有符合条件的教材';

  /// 筛选无结果说明。
  static const String noResultHint = '换个关键词，或放宽筛选条件试试';

  // ==================== 教材详情 ====================

  /// 详情缺失时的说明。
  ///
  /// 平台上有少数条目只有子资源、没有独立的详情，属于正常情况，
  /// 文案要说清"这本看不了"，而不是让用户以为是网络或权限问题。
  static const String detailUnavailable = '该教材暂不提供在线阅读';

  /// 页数标签。
  static const String detailPageCount = '页数';

  /// 文件大小标签。
  static const String detailFileSize = '大小';

  /// 出版社标签。
  static const String detailProvider = '出版社';

  /// 分类标签。
  static const String detailCategory = '分类';

  /// 开始阅读。
  static const String detailRead = '在线阅读';

  /// 下载。
  static const String detailDownload = '下载';

  /// 未登录时的下载提示。
  static const String detailNeedLogin = '登录后可下载';

  /// 已下载。
  static const String detailDownloaded = '已下载';

  /// 页数，如「128 页」。
  static String pageCount(int count) => '$count 页';

  // ==================== 登录 ====================

  /// 登录页标题。
  static const String loginTitle = '登录';

  /// 已完成登录。
  static const String loginDone = '我已登好';

  /// 登录页说明。
  static const String loginHint = '请在下方页面登录，登录成功后会自动返回。凭据只保存在本机，不会上传。';

  /// 登录成功。
  static const String loginSucceeded = '登录成功';

  /// 退出登录。
  static const String logout = '退出登录';

  /// 退出登录确认。
  static const String logoutConfirmTitle = '退出登录？';

  /// 退出登录确认正文。
  static const String logoutConfirmBody = '退出后将无法下载需要登录的教材，已下载的内容不受影响。';

  /// 登录态分组标题。
  static const String settingsAccount = '账号';

  /// 已登录标签。
  static const String settingsLoggedIn = '已登录';

  /// 未登录标签。
  static const String settingsNotLoggedIn = '未登录';

  /// 安全存储不可用时的提示。
  static const String settingsSessionOnly = '系统安全存储不可用，本次登录在退出应用后失效';

  // ==================== 书架与下载 ====================

  /// 藏书量，如「共 12 本」。
  static String libraryCount(int count) => '共 $count 本';

  /// 选择。
  static const String select = '选择';

  /// 全选。
  static const String selectAll = '全选';

  /// 完成。
  static const String done = '完成';

  /// 置顶。既是操作条上的按钮，也是书架置顶区的标题。
  static const String libraryPin = '置顶';

  /// 取消置顶。选中的书**全都已置顶**时，那个按钮就变成这个动作。
  static const String libraryUnpin = '取消置顶';

  /// 书架分区的兜底标题：既没置顶、也没归组的书。
  static const String libraryUngrouped = '未分组';

  /// 分区标题右侧的本数，如「3 本」。
  static String librarySectionCount(int count) => '$count 本';

  /// 分组到。
  static const String libraryGroup = '分组到';

  /// 分组对话框标题。
  static const String libraryGroupTitle = '分组到';

  /// 新建分组的输入提示。
  static const String libraryGroupNewHint = '输入新分组名';

  /// 还没有任何分组时的提示。
  static const String libraryGroupEmpty = '还没有分组，在下方输入一个名字即可新建。';

  /// 已归入分组。
  static String libraryGrouped(String group, int count) =>
      '已将 $count 本归入「$group」';

  /// 已移出分组。
  static const String libraryGroupRemoved = '已移出分组';

  /// 移出分组。
  static const String libraryGroupRemove = '移出分组';

  /// 分享。
  static const String libraryShare = '分享';

  /// 分享多份时的标题。
  static String libraryShareSubject(int count) => '分享 $count 本教材';

  /// 移出书架。
  static const String libraryRemove = '移出书架';

  /// 移出书架确认标题。
  static String libraryRemoveConfirmTitle(int count) =>
      count == 1 ? '移出这本教材？' : '移出这 $count 本教材？';

  /// 移出书架确认正文。
  static const String libraryRemoveConfirmBody =
      '本地文件会被删除，阅读进度也会一并清除。需要时可以在目录里重新下载。';

  /// 书架空态标题。
  static const String libraryEmptyTitle = '书架还是空的';

  /// 书架空态说明。
  static const String libraryEmptyHint = '去「目录」里挑几本教材下载，下载完就会出现在这里';

  /// 下载页空态标题。
  static const String downloadsEmptyTitle = '没有下载任务';

  /// 下载页空态说明。
  static const String downloadsEmptyHint = '在目录里勾选教材后点「下载选中」即可加入队列';

  // ==================== 设置 ====================

  /// 分组标题：教材目录。
  static const String settingsCatalog = '教材目录';

  /// 分组标题：关于。
  static const String settingsAbout = '关于';

  /// 教材总数标签。
  static const String settingsCatalogCount = '教材数量';

  /// 磁盘占用标签。
  static const String settingsCatalogSize = '占用空间';

  /// 重新下载目录。
  static const String settingsCatalogRedownload = '重新下载目录';

  /// 清除本地目录数据。
  static const String settingsCatalogClear = '清除本地数据';

  /// 清除确认对话框标题。
  static const String settingsCatalogClearConfirmTitle = '清除本地教材目录？';

  /// 清除确认对话框正文。
  static const String settingsCatalogClearConfirmBody =
      '清除后需要重新下载约 40 MB 数据。已下载的教材正文不受影响。';

  /// 目录已清除的提示。
  static const String settingsCatalogCleared = '本地目录数据已清除';

  /// 尚未下载目录。
  static const String settingsCatalogNotReady = '尚未下载';

  /// 版本号标签。
  static const String settingsVersion = '版本';

  /// 免责声明标题。
  static const String settingsDisclaimer = '免责声明';

  /// 免责声明正文。
  static const String settingsDisclaimerBody =
      '本应用是第三方客户端，与国家中小学智慧教育平台没有隶属或合作关系。\n\n'
      '应用内展示与下载的教材版权归原平台及相关权利人所有，'
      '仅供个人学习与教学参考，请勿用于商业用途或二次分发。\n\n'
      '请遵守平台的服务条款及当地法律法规,一起促进教育公平！';

  // ==================== 离线 ====================

  /// 离线提示。
  static const String offlineBanner = '当前处于离线状态，部分内容可能不是最新';
}
