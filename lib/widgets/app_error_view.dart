import 'package:flutter/material.dart';

import '../utils/utils.dart';
import '../values/values.dart';

/// 统一的错误态。
///
/// 关键设计：**只有当失败可重试时才显示"重试"按钮**。
/// 参数错误、解析失败、无权限这些情况重试多少次都一样，
/// 给一个按不出结果的按钮只会让用户反复点击。
/// 判断逻辑由 `AppFailure.isRetryable` 扩展统一提供，页面不必自己写 `if`。
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  /// 直接展示的错误文案。
  final String message;

  /// 重试回调；为空时不显示重试按钮。
  final VoidCallback? onRetry;

  /// 顶部图标。
  final IconData icon;

  /// 由失败对象构造。
  ///
  /// 传入 `onRetry` 时，会自动按 `AppFailure.isRetryable` 决定是否展示按钮。
  factory AppErrorView.fromFailure(
    AppFailure failure, {
    Key? key,
    VoidCallback? onRetry,
  }) => AppErrorView(
    key: key,
    message: failure.message,
    onRetry: failure.isRetryable ? onRetry : null,
    icon: switch (failure) {
      NetworkFailure() => Icons.wifi_off_rounded,
      ServerFailure() => Icons.cloud_off_rounded,
      AuthFailure() => Icons.lock_outline_rounded,
      BusinessFailure() => Icons.info_outline_rounded,
      CancelledFailure() => Icons.cancel_outlined,
      ClientFailure() => Icons.error_outline_rounded,
      ParseFailure() => Icons.data_object_rounded,
      CacheFailure() => Icons.sd_card_alert_outlined,
      UnknownFailure() => Icons.error_outline_rounded,
    },
  );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final VoidCallback? onRetry = this.onRetry;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: AppDimens.iconXl, color: scheme.error),
            SizedBox(height: AppDimens.gapLg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDimens.fontBodySmall,
                color: scheme.onSurfaceVariant,
                height: AppDimens.lineHeightNormal,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              SizedBox(height: AppDimens.gapLg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded, size: AppDimens.iconSm),
                label: const Text(AppStrings.retry),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(
                    AppDimens.buttonHeight * 2.4,
                    AppDimens.buttonHeight,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
