import 'package:flutter/material.dart';

import '../values/values.dart';

/// 统一的空态。
///
/// 空态文案分两行：[title] 说明"没有数据"，[hint] 告诉用户"接下来可以做什么"。
/// 只写前者会让人以为页面坏了。
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.title = AppStrings.empty,
    this.hint,
    this.action,
  });

  /// 顶部图标。
  final IconData icon;

  /// 主文案。
  final String title;

  /// 补充说明。
  final String? hint;

  /// 操作入口，例如"刷新"或"去创建"。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? hint = this.hint;
    final Widget? action = this.action;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: AppDimens.iconXl, color: scheme.outline),
            SizedBox(height: AppDimens.gapLg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDimens.fontBody,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            if (hint != null) ...<Widget>[
              SizedBox(height: AppDimens.gapXs),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppDimens.fontBodySmall,
                  color: scheme.onSurfaceVariant,
                  height: AppDimens.lineHeightNormal,
                ),
              ),
            ],
            if (action != null) ...<Widget>[
              SizedBox(height: AppDimens.gapLg),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
