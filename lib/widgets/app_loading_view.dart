import 'package:flutter/material.dart';

import '../values/values.dart';

/// 统一的加载态。
///
/// 全应用只保留一种加载样式，避免每个页面各写一个 `CircularProgressIndicator`
/// 导致尺寸、间距、配色各不相同。
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.message, this.compact = false});

  /// 加载提示文案，为空时只显示转圈。
  final String? message;

  /// 紧凑模式：用于列表底部"加载更多"，尺寸更小且不占满高度。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? message = this.message;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppDimens.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: compact ? AppDimens.iconMd : AppDimens.iconLg,
              height: compact ? AppDimens.iconMd : AppDimens.iconLg,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: scheme.primary,
              ),
            ),
            if (message != null) ...<Widget>[
              SizedBox(height: AppDimens.gapMd),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppDimens.fontBodySmall,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
