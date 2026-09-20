import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/catalog_provider.dart';
import '../../services/catalog/catalog.dart';
import '../../utils/utils.dart';
import '../../values/values.dart';
import '../../widgets/widgets.dart';

/// 教材目录的准备页：首次下载、更新、失败重试。
///
/// 目录数据约 40MB，是第一版没有它就什么都做不了的前置条件，
/// 因此这一页要把三件事说清楚：**为什么需要下载、要下多久、失败了怎么办**。
///
/// 它有两种用法：
/// - 作为首屏（`HomeShell` 在目录未就绪时占住整个外壳）；
/// - 作为全屏页（设置页的"重新下载目录"）。
class CatalogSetupPage extends StatelessWidget {
  const CatalogSetupPage({super.key, this.showAppBar = false});

  /// 是否显示顶栏。作为首屏时为 `false`，作为全屏页时为 `true`。
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();

    final Widget body = switch (catalog.status) {
      CatalogStatus.loading => _Progress(progress: catalog.progress),
      CatalogStatus.failed => AppErrorView.fromFailure(
        catalog.failure ??
            const UnknownFailure(message: AppStrings.errorUnknown),
        onRetry: () => context.read<CatalogProvider>().download(),
      ),
      CatalogStatus.idle ||
      CatalogStatus.needsDownload ||
      CatalogStatus.ready => _Introduction(
        catalog: catalog,
        onDownload: () => _download(context),
      ),
    };

    if (!showAppBar) {
      return Scaffold(body: SafeArea(child: body));
    }
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.catalogSetupTitle)),
      body: body,
    );
  }
}

/// 触发下载，并在完成后给反馈。
///
/// 只有作为全屏页（从设置进入）时才提示：作为首屏时下载成功会直接把整块
/// 界面换成 Tab 外壳，这里的 context 已经失效，提示也没有意义。
Future<void> _download(BuildContext context) async {
  final bool fullScreen = context.findAncestorWidgetOfExactType<Scaffold>() != null;
  await context.read<CatalogProvider>().download();
  if (!context.mounted) {
    return;
  }
  final CatalogProvider provider = context.read<CatalogProvider>();
  if (provider.status == CatalogStatus.failed) {
    return; // 失败由页面上的错误视图呈现，不必再弹一条。
  }
  context.showSnackBar(
    fullScreen
        ? AppStrings.catalogUpdated(provider.bookCount)
        : AppStrings.catalogReady,
  );
}

/// 首次进入的介绍与下载入口。
class _Introduction extends StatelessWidget {
  const _Introduction({required this.catalog, required this.onDownload});

  final CatalogProvider catalog;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool hasData = catalog.hasData;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding * 1.5),
        // 宽窗口下限制内容宽度：整页提示居中铺满 1500px 会显得很空，
        // 也会让一行文字过长而难以阅读。
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppDimens.contentMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.library_books_rounded,
                size: AppDimens.iconDisplay,
                color: scheme.primary,
              ),
              SizedBox(height: AppDimens.gapLg),
              Text(
                hasData
                    ? AppStrings.catalogRefreshTitle
                    : AppStrings.catalogSetupTitle,
                style: TextStyle(
                  fontSize: AppDimens.fontTitle,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              SizedBox(height: AppDimens.gapSm),
              Text(
                hasData
                    ? AppStrings.catalogRefreshHint
                    : AppStrings.catalogSetupHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppDimens.fontBodySmall,
                  color: scheme.onSurfaceVariant,
                  height: AppDimens.lineHeightLoose,
                ),
              ),
              SizedBox(height: AppDimens.gapXl),
              FilledButton.icon(
                onPressed: onDownload,
                icon: Icon(
                  hasData
                      ? Icons.refresh_rounded
                      : Icons.cloud_download_rounded,
                  size: AppDimens.iconSm,
                ),
                label: Text(
                  hasData
                      ? AppStrings.refresh
                      : AppStrings.catalogDownloadAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 下载与解析进度。
class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final CatalogProgress progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? fraction = progress.fraction;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding * 1.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _stageLabel(progress),
              style: TextStyle(
                fontSize: AppDimens.fontBody,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            SizedBox(height: AppDimens.gapLg),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              child: LinearProgressIndicator(
                // fraction 为 null 表示进度不确定，交给控件画不确定态动画，
                // 比停在一个假的百分比上诚实。
                value: fraction,
                minHeight: AppDimens.progressHeight,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            if (fraction != null) ...<Widget>[
              SizedBox(height: AppDimens.gapSm),
              Text(
                '${(fraction * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: AppDimens.fontBodySmall,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: AppDimens.gapLg),
            Text(
              AppStrings.catalogSetupKeepOpen,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDimens.fontCaption,
                color: scheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 把阶段翻译成用户看得懂的一句话。
  static String _stageLabel(CatalogProgress progress) {
    switch (progress.stage) {
      case CatalogStage.idle:
        return AppStrings.loading;
      case CatalogStage.checking:
        return AppStrings.catalogStageChecking;
      case CatalogStage.downloading:
        if (progress.totalParts == 0) {
          return AppStrings.catalogStageDownloading;
        }
        return '${AppStrings.catalogStageDownloading}'
            '（${progress.completedParts + 1}/${progress.totalParts}）';
      case CatalogStage.parsing:
        return AppStrings.catalogStageParsing;
      case CatalogStage.indexing:
        return AppStrings.catalogStageIndexing;
      case CatalogStage.ready:
        return AppStrings.catalogStageReady;
      case CatalogStage.failed:
        return AppStrings.errorUnknown;
    }
  }
}
