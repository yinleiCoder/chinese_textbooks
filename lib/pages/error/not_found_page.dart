import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/router/app_routes.dart';
import '../../values/values.dart';

/// 404 页面。
///
/// 路由未匹配时由 `AppNavigator.errorBuilder` 渲染。
/// 之所以不用 Flutter 默认的错误屏：它只显示一行红色英文堆栈提示，
/// 对用户毫无意义，也不符合应用的视觉规范。
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, this.location});

  /// 触发 404 的原始地址，便于用户反馈问题时提供线索。
  final String? location;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? location = this.location;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.pageNotFound)),
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.explore_off_outlined,
                size: AppDimens.iconDisplay,
                color: scheme.outline,
              ),
              SizedBox(height: AppDimens.gapLg),
              Text(
                AppStrings.pageNotFound,
                style: TextStyle(
                  fontSize: AppDimens.fontSubtitle,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              SizedBox(height: AppDimens.gapXs),
              Text(
                AppStrings.pageNotFoundHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppDimens.fontBodySmall,
                  color: scheme.onSurfaceVariant,
                  height: AppDimens.lineHeightNormal,
                ),
              ),
              if (location != null) ...<Widget>[
                SizedBox(height: AppDimens.gapMd),
                Text(
                  location,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppDimens.fontCaption,
                    color: scheme.outline,
                  ),
                ),
              ],
              SizedBox(height: AppDimens.gapXl),
              FilledButton(
                onPressed: () => context.goNamed(AppRoutes.libraryName),
                child: const Text(AppStrings.backToHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
