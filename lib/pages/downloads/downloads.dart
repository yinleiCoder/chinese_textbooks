import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../entity/entity.dart';
import '../../providers/providers.dart';
import '../../utils/utils.dart';
import '../../values/values.dart';
import '../../widgets/widgets.dart';
import '../shell/home_shell.dart';

/// 下载页。
///
/// 独立成一个 Tab 是刻意的：参考项目在 52pojie 上被诟病最多的一条就是
/// "批量下载时界面无响应、看不到哪本失败"。把队列、进度、失败原因放在
/// 一眼能看到的地方，比弹窗通知有效得多。
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DownloadProvider downloads = context.watch<DownloadProvider>();

    final Widget body;
    if (downloads.isResolving) {
      body = AppLoadingView(
        message:
            '${AppStrings.downloadResolving}'
            '（${downloads.resolvedCount}/${downloads.resolveTotal}）',
      );
    } else if (downloads.tasks.isEmpty) {
      body = const AppEmptyView(
        icon: Icons.download_done_outlined,
        title: AppStrings.downloadsEmptyTitle,
        hint: AppStrings.downloadsEmptyHint,
      );
    } else {
      body = Column(
        children: <Widget>[
          const _Summary(),
          Expanded(
            child: ListView.builder(
              itemCount: downloads.tasks.length,
              itemBuilder: (BuildContext context, int index) =>
                  _TaskTile(task: downloads.tasks[index]),
            ),
          ),
        ],
      );
    }

    return ShellPageScaffold(title: AppStrings.tabDownloads, child: body);
  }
}

/// 队列概览：几条失败、几个进行中，以及批量操作。
class _Summary extends StatelessWidget {
  const _Summary();

  @override
  Widget build(BuildContext context) {
    final DownloadProvider downloads = context.watch<DownloadProvider>();
    final int failed = downloads.tasks
        .where((DownloadTask t) => t.status == DownloadStatus.failed)
        .length;
    final int done = downloads.tasks
        .where((DownloadTask t) => t.status == DownloadStatus.completed)
        .length;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppDimens.gapXs),
      child: Row(
        children: <Widget>[
          Text(
            AppStrings.downloadSummary(done, downloads.tasks.length),
            style: TextStyle(
              fontSize: AppDimens.fontBodySmall,
              color: context.secondaryTextColor,
            ),
          ),
          const Spacer(),
          if (failed > 0)
            TextButton(
              onPressed: () =>
                  context.read<DownloadProvider>().retryAllFailed(),
              child: Text(AppStrings.downloadRetryAllFailed(failed)),
            ),
          if (done > 0)
            TextButton(
              onPressed: () =>
                  context.read<DownloadProvider>().clearCompleted(),
              child: const Text(AppStrings.downloadClearCompleted),
            ),
        ],
      ),
    );
  }
}

/// 单个任务。
class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? progress = task.progress;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppDimens.gapXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDimens.fontBodySmall,
                    height: AppDimens.lineHeightNormal,
                  ),
                ),
              ),
              SizedBox(width: AppDimens.gapXs),
              _action(context, scheme),
            ],
          ),
          SizedBox(height: AppDimens.gapXxs),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: AppDimens.progressHeight / 2,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: task.status == DownloadStatus.failed
                        ? scheme.error
                        : scheme.primary,
                  ),
                ),
              ),
              SizedBox(width: AppDimens.gapSm),
              Text(
                _statusText(task),
                style: TextStyle(
                  fontSize: AppDimens.fontCaption,
                  color: task.status == DownloadStatus.failed
                      ? scheme.error
                      : context.secondaryTextColor,
                ),
              ),
            ],
          ),
          // 失败原因原样展示，而不是笼统的"下载失败"。
          // 用户看到"需要登录"就知道该去登录，看到"限流"就知道该等一等。
          if (task.message != null && task.status == DownloadStatus.failed)
            Padding(
              padding: EdgeInsets.only(top: AppDimens.gapXxs),
              child: Text(
                task.message!,
                style: TextStyle(
                  fontSize: AppDimens.fontCaption,
                  color: scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, ColorScheme scheme) {
    final DownloadProvider provider = context.read<DownloadProvider>();
    switch (task.status) {
      case DownloadStatus.completed:
        return Icon(
          Icons.check_circle_rounded,
          size: AppDimens.iconSm,
          color: scheme.primary,
        );
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return IconButton(
          onPressed: task.canRetry
              ? () => provider.retry(task.textbookId)
              : null,
          icon: Icon(Icons.refresh_rounded, size: AppDimens.iconSm),
          tooltip: AppStrings.retry,
          visualDensity: VisualDensity.compact,
        );
      case DownloadStatus.queued:
      case DownloadStatus.running:
        return IconButton(
          onPressed: () => provider.cancel(task.textbookId),
          icon: Icon(Icons.close_rounded, size: AppDimens.iconSm),
          tooltip: AppStrings.cancel,
          visualDensity: VisualDensity.compact,
        );
    }
  }

  static String _statusText(DownloadTask task) {
    return switch (task.status) {
      DownloadStatus.queued => AppStrings.downloadQueued,
      // 进度 + 已下载量 + 速度。只给百分比的话，"慢"这件事完全没有依据，
      // 用户只能凭感觉说"很慢"。
      DownloadStatus.running => _runningText(task),
      DownloadStatus.completed => AppStrings.detailDownloaded,
      DownloadStatus.failed => AppStrings.downloadFailed,
      DownloadStatus.cancelled => AppStrings.downloadCancelled,
    };
  }

  static String _runningText(DownloadTask task) {
    final StringBuffer buffer = StringBuffer();
    if (task.progress != null) {
      buffer
        ..write((task.progress! * 100).toStringAsFixed(0))
        ..write('%');
    } else {
      buffer.write(AppStrings.downloadRunning);
    }
    if (task.expectedBytes > 0) {
      buffer
        ..write(' · ')
        ..write(formatBytes(task.receivedBytes))
        ..write('/')
        ..write(formatBytes(task.expectedBytes));
    }
    if (task.bytesPerSecond > 0) {
      buffer
        ..write(' · ')
        ..write(formatSpeed(task.bytesPerSecond));
    }
    return buffer.toString();
  }
}
