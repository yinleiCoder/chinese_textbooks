import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../values/values.dart';

/// 欢迎页。
///
/// 目前只承担"应用骨架是否装配正确"的验证职责：
/// 它同时消费了 `values`（主题与尺寸）、`providers`（状态）和
/// `widgets`（公共组件）三层，能跑通就说明依赖注入、路由、
/// 屏幕适配与深色模式都已就位。
///
/// 业务页面请在 `pages/` 下新建独立目录实现，不要往这里堆功能。
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppConnectivityProvider connectivity = context
        .watch<AppConnectivityProvider>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (connectivity.isOffline) const _OfflineBanner(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppDimens.pagePadding * 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.menu_book_rounded,
                        size: AppDimens.iconHero,
                        color: scheme.primary,
                      ),
                      SizedBox(height: AppDimens.gapLg),
                      Text(
                        AppStrings.welcomeTitle,
                        style: TextStyle(
                          fontSize: AppDimens.fontDisplay,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                          height: AppDimens.lineHeightTight,
                        ),
                      ),
                      SizedBox(height: AppDimens.gapXs),
                      Text(
                        AppStrings.welcomeSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppDimens.fontBody,
                          color: scheme.onSurfaceVariant,
                          height: AppDimens.lineHeightLoose,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 离线提示条。
///
/// 复用了 `AppConnectivityProvider`，说明"离线"这个状态
/// 在任意页面都能直接拿到，不需要各页面自己订阅。
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapXs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.cloud_off_rounded,
            size: AppDimens.iconSm,
            color: scheme.onErrorContainer,
          ),
          SizedBox(width: AppDimens.gapXs),
          Flexible(
            child: Text(
              AppStrings.offlineBanner,
              style: TextStyle(
                fontSize: AppDimens.fontCaption,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
