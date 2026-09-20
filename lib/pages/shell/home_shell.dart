import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/catalog_provider.dart';
import '../../values/values.dart';
import '../catalog/catalog_setup_page.dart';

/// 应用外壳：四个 Tab 的容器，同时也是**目录加载状态的分流点**。
///
/// ## 为什么在这里分流，而不是用路由 `redirect`
///
/// go_router 的 `redirect` 是同步的，而目录加载是异步的。
/// 用它做"未加载就跳转"极易陷入"未加载 → 跳转 → 又未加载"的循环，
/// 而且跳转会留下一条用户按返回键会撞上的历史记录。
/// 直接在构建时按状态渲染，没有历史记录，也没有循环。
///
/// ## 平台差异
///
/// 宽屏（≥720dp，Windows 与平板）用左侧 `NavigationRail`，
/// 窄屏用底部 `NavigationBar`。这是本应用唯一的响应式分支点，
/// 集中在这里而不是散落到各页面。
class HomeShell extends StatefulWidget {
  const HomeShell({required this.navigationShell, super.key});

  /// go_router 的分支外壳，四个 Tab 各自维护独立的导航栈。
  final StatefulNavigationShell navigationShell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    // 放到首帧之后：initialize() 会同步地把状态置为 loading 并通知监听者，
    // 在 build 期间触发会报错。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CatalogProvider>().initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();

    // 没有目录数据时，整块外壳让给准备页——四个 Tab 此时都没有内容可展示。
    if (!catalog.hasData) {
      return const CatalogSetupPage();
    }

    final bool wide = MediaQuery.sizeOf(context).width >= 720;
    if (!wide) {
      return Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: _buildNavigationBar(context),
      );
    }

    return Scaffold(
      body: Row(
        children: <Widget>[
          _buildNavigationRail(context),
          const VerticalDivider(width: 1),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }

  NavigationBar _buildNavigationBar(BuildContext context) {
    return NavigationBar(
      selectedIndex: widget.navigationShell.currentIndex,
      onDestinationSelected: _goBranch,
      destinations: _destinations
          .map(
            (_Destination item) => NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
          )
          .toList(growable: false),
    );
  }

  NavigationRail _buildNavigationRail(BuildContext context) {
    return NavigationRail(
      selectedIndex: widget.navigationShell.currentIndex,
      onDestinationSelected: _goBranch,
      labelType: NavigationRailLabelType.all,
      destinations: _destinations
          .map(
            (_Destination item) => NavigationRailDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: Text(item.label),
            ),
          )
          .toList(growable: false),
    );
  }

  /// 切换分支。
  ///
  /// `initialLocation: true` 表示再次点击当前 Tab 时回到该分支的根页面——
  /// 这是各平台导航的通行约定（在详情页里点当前 Tab 应当回到列表）。
  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  static const List<_Destination> _destinations = <_Destination>[
    _Destination(
      icon: Icons.shelves,
      selectedIcon: Icons.shelves,
      label: AppStrings.tabLibrary,
    ),
    _Destination(
      icon: Icons.account_tree_outlined,
      selectedIcon: Icons.account_tree,
      label: AppStrings.tabBrowse,
    ),
    _Destination(
      icon: Icons.download_outlined,
      selectedIcon: Icons.download,
      label: AppStrings.tabDownloads,
    ),
    _Destination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: AppStrings.tabSettings,
    ),
  ];
}

/// 一个 Tab 的图标与标题。
final class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Tab 页统一的内边距与标题，避免四个页面各写一套。
class ShellPageScaffold extends StatelessWidget {
  const ShellPageScaffold({
    required this.title,
    required this.child,
    this.actions,
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppDimens.gapSm),
          child: child,
        ),
      ),
    );
  }
}
