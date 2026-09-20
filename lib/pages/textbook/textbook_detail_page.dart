import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../apis/apis.dart';
import '../../entity/entity.dart';
import '../../providers/providers.dart';
import '../../services/catalog/catalog.dart';
import '../../services/router/app_routes.dart';
import '../../utils/utils.dart';
import '../../values/values.dart';
import '../../widgets/widgets.dart';
import 'textbook_detail_provider.dart';

/// 教材详情页。
///
/// 数据来源有两处，各有分工：
/// - **清单**（`CatalogProvider`）给出分类路径与出版社；
/// - **详情接口**给出页数、体积与 PDF 地址。
///
/// 详情接口偶尔会对某些条目返回 403（只有子资源、没有独立详情），
/// 这种情况由 `TextbookApi` 归类成 `detailUnavailable`，页面显示
/// "暂不提供在线阅读"，而不是"没有访问权限"。
class TextbookDetailPage extends StatefulWidget {
  const TextbookDetailPage({required this.contentId, super.key, this.summary});

  /// 教材 id。
  final String contentId;

  /// 从目录页带过来的清单条目，深链进入时为 `null`。
  final Textbook? summary;

  @override
  State<TextbookDetailPage> createState() => _TextbookDetailPageState();
}

class _TextbookDetailPageState extends State<TextbookDetailPage> {
  late final TextbookDetailProvider _provider = TextbookDetailProvider(
    api: context.read<TextbookApi>(),
    contentId: widget.contentId,
    summary: widget.summary,
  );

  @override
  void initState() {
    super.initState();
    // 首帧之后再触发：load() 会同步地把状态置为 loading 并通知监听者。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _provider.load();
      }
    });
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TextbookDetailProvider>.value(
      value: _provider,
      child: const _DetailView(),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    final TextbookDetailProvider provider = context
        .watch<TextbookDetailProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(provider.title, overflow: TextOverflow.ellipsis),
      ),
      body: switch (provider.status) {
        DetailStatus.loading => const AppLoadingView(),
        DetailStatus.failed => AppErrorView.fromFailure(
          provider.failure ??
              const UnknownFailure(message: AppStrings.errorUnknown),
          onRetry: () => context.read<TextbookDetailProvider>().load(),
        ),
        DetailStatus.ready => const _Content(),
      },
      bottomNavigationBar: provider.status == DetailStatus.ready
          ? const _ActionBar()
          : null,
    );
  }
}

/// 详情内容。
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final TextbookDetailProvider provider = context
        .watch<TextbookDetailProvider>();
    final TextbookDetail? detail = provider.detail;
    if (detail == null) {
      return const SizedBox.shrink();
    }

    final CatalogIndex? index = context.watch<CatalogProvider>().index;
    final Textbook? summary = provider.summary;
    final String category = summary == null || index == null
        ? ''
        : index.categoryPathOf(summary);

    return SingleChildScrollView(
      padding: EdgeInsets.all(AppDimens.pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppDimens.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: SizedBox(
                  width: 160,
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: detail.previewUrl == null
                        ? _coverPlaceholder(context)
                        : AppNetworkImage(
                            url: detail.previewUrl!,
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusMd,
                            ),
                          ),
                  ),
                ),
              ),
              SizedBox(height: AppDimens.gapLg),
              Text(
                detail.title,
                style: TextStyle(
                  fontSize: AppDimens.fontSubtitle,
                  fontWeight: FontWeight.w700,
                  height: AppDimens.lineHeightTight,
                ),
              ),
              SizedBox(height: AppDimens.gapMd),
              // 只有详情接口能给的：页数与体积。
              // 平台没有给出文件时（页面数/体积为空）就整行不显示，
              // 而不是显示"未知"——那只会让人以为是加载失败。
              if (detail.pageCount != null)
                _InfoRow(
                  label: AppStrings.detailPageCount,
                  value: AppStrings.pageCount(detail.pageCount!),
                ),
              if (detail.sizeBytes != null)
                _InfoRow(
                  label: AppStrings.detailFileSize,
                  value: detail.readableSize,
                ),
              // 只有清单能给的：分类与出版社。
              if (category.isNotEmpty)
                _InfoRow(label: AppStrings.detailCategory, value: category),
              if (summary?.providerName != null)
                _InfoRow(
                  label: AppStrings.detailProvider,
                  value: summary!.providerName!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: AppDimens.iconXl,
          color: scheme.outline,
        ),
      ),
    );
  }
}

/// 一行"标签：值"。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppDimens.gapXxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppDimens.fontBodySmall,
                color: context.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppDimens.fontBodySmall,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 加入下载队列，并给出明确反馈。
///
/// 入队不是瞬时的：要先请求详情拿到 PDF 地址。用户点完按钮后如果什么都没
/// 发生，会以为没点上——所以先给一句"正在解析"，完成后换成结果加一个去处。
Future<void> _enqueue(BuildContext context, Textbook? summary) async {
  if (summary == null) {
    context.showSnackBar(AppStrings.downloadNeedCatalog);
    return;
  }
  final DownloadProvider downloads = context.read<DownloadProvider>();
  context.showSnackBar(AppStrings.downloadResolving);
  await downloads.enqueue(<Textbook>[summary]);
  if (!context.mounted) {
    return;
  }
  context.showSnackBarWithAction(
    AppStrings.downloadEnqueued(1),
    actionLabel: AppStrings.downloadView,
    onAction: () => context.goNamed(AppRoutes.downloadsName),
  );
}

/// 底部操作条。
///
/// 按钮文案按"能不能下"分三种，把限制**提前讲清楚**，而不是等用户
/// 点了才弹失败：
/// - 有源文件且已登录 → 「下载」；
/// - 有源文件但未登录 → 「登录后可下载」（点一下引导登录）；
/// - 没有源文件 → 一个禁用按钮 + 「暂不提供在线阅读」。
class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final TextbookDetailProvider provider = context
        .watch<TextbookDetailProvider>();
    final bool downloadable = provider.isDownloadable;
    final bool loggedIn = context.watch<AuthSessionProvider>().isLoggedIn;
    final Textbook? summary = provider.summary;
    // 按磁盘判断，不按任务表——重启后任务表是空的，而文件还在。
    final bool downloaded = context.watch<LibraryProvider>().isDownloaded(
      provider.contentId,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(AppDimens.pagePadding),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: !downloadable || downloaded
                    ? null
                    // 未登录就先去登录，而不是弹一句"请先登录"再让用户
                    // 自己去找入口——那多一步毫无意义。
                    : loggedIn
                    ? () => unawaited(_enqueue(context, summary))
                    : () => context.pushNamed(AppRoutes.loginName),
                icon: Icon(
                  downloaded
                      ? Icons.check_circle_rounded
                      : (downloadable
                            ? Icons.download_rounded
                            : Icons.block_rounded),
                  size: AppDimens.iconSm,
                ),
                label: Text(
                  downloaded
                      ? AppStrings.detailDownloaded
                      : (!downloadable
                            ? AppStrings.detailUnavailable
                            : (loggedIn
                                  ? AppStrings.detailDownload
                                  : AppStrings.detailNeedLogin)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
