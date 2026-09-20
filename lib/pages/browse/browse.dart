import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../entity/entity.dart';
import '../../providers/providers.dart';
import '../../services/catalog/catalog.dart';
import '../../services/router/app_routes.dart';
import '../../utils/utils.dart';
import '../../values/values.dart';
import '../../widgets/widgets.dart';
import '../shell/home_shell.dart';
import 'browse_provider.dart';
import 'browse_row.dart';

/// 目录页：分类树 / 筛选 / 搜索 / 多选。
///
/// 两种形态共用一个 `ListView.builder`：
/// - **树模式**：按展开状态把分类树拍平成行，教材作为叶子内联显示；
/// - **列表模式**：一旦有筛选条件或搜索词就切成扁平结果——
///   树在结果稀疏时会退化成一堆只有一个孩子的节点，逐层点进去找书
///   远不如直接列出来。
///
/// 勾选状态与筛选条件**互不影响**：它只认教材 id，所以用户可以在
/// 几个不同筛选条件下分几次勾选，最后一起下载。
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  BrowseProvider? _browse;
  CatalogIndex? _boundIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 目录索引会被后台更新替换掉。索引一换，展开状态与勾选集合里的节点 id
    // 就可能失效，因此整体重建浏览状态——这是正确性优先于"保留现场"的选择。
    final CatalogIndex? index = context.watch<CatalogProvider>().index;
    if (index != null && !identical(index, _boundIndex)) {
      _browse?.dispose();
      _browse = BrowseProvider(index: index);
      _boundIndex = index;
    }
  }

  @override
  void dispose() {
    _browse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BrowseProvider? browse = _browse;
    if (browse == null) {
      return const ShellPageScaffold(
        title: AppStrings.tabBrowse,
        child: AppLoadingView(),
      );
    }
    return ChangeNotifierProvider<BrowseProvider>.value(
      value: browse,
      child: const _BrowseView(),
    );
  }
}

/// 目录页的界面。
class _BrowseView extends StatelessWidget {
  const _BrowseView();

  @override
  Widget build(BuildContext context) {
    final BrowseProvider browse = context.watch<BrowseProvider>();

    return ShellPageScaffold(
      title: AppStrings.tabBrowse,
      child: Column(
        children: <Widget>[
          AppSearchField(
            value: browse.query,
            onChanged: (String value) =>
                context.read<BrowseProvider>().setQuery(value),
          ),
          SizedBox(height: AppDimens.gapSm),
          AppFilterBar(
            facets: browse.index.facets,
            filter: browse.filter,
            onOpenSheet: () => _openFilterSheet(context, browse),
            onRemove: (String dimensionId, String tagId) =>
                context.read<BrowseProvider>().toggleFilter(dimensionId, tagId),
            onClearAll: () => context.read<BrowseProvider>().clearAllFilters(),
          ),
          const _ResultSummary(),
          Expanded(child: _Body(browse: browse)),
          const _SelectionBar(),
        ],
      ),
    );
  }

  Future<void> _openFilterSheet(
    BuildContext context,
    BrowseProvider browse,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => AppFilterSheet(
        facets: browse.index.facets,
        initialFilter: browse.filter,
        onChanged: (CatalogFilter filter) {
          // 弹层是独立路由，拿不到页面里的 Provider，
          // 因此用外部传入的 browse 直接驱动状态。
          final CatalogFilter current = browse.filter;
          // 只同步差异，避免每次勾选都把整个条件重设一遍。
          for (final String dimensionId in <String>{
            ...current.selectedByDimension.keys,
            ...filter.selectedByDimension.keys,
          }) {
            final Set<String> before = current.selectedIn(dimensionId);
            final Set<String> after = filter.selectedIn(dimensionId);
            for (final String tagId in before.difference(after)) {
              browse.toggleFilter(dimensionId, tagId);
            }
            for (final String tagId in after.difference(before)) {
              browse.toggleFilter(dimensionId, tagId);
            }
          }
        },
      ),
    );
  }
}

/// 结果概览：数量 + 展开 / 收起。
class _ResultSummary extends StatelessWidget {
  const _ResultSummary();

  @override
  Widget build(BuildContext context) {
    final BrowseProvider browse = context.watch<BrowseProvider>();
    final bool treeMode = browse.mode == BrowseMode.tree;
    final int count = treeMode ? browse.index.length : browse.results.length;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppDimens.gapXs),
      child: Row(
        children: <Widget>[
          Text(
            AppStrings.resultCount(count),
            style: TextStyle(
              fontSize: AppDimens.fontBodySmall,
              color: context.secondaryTextColor,
            ),
          ),
          const Spacer(),
          if (treeMode)
            TextButton.icon(
              onPressed: () {
                final BrowseProvider provider = context.read<BrowseProvider>();
                if (browse.hasExpanded) {
                  provider.collapseAll();
                } else {
                  provider.expandAll();
                }
              },
              icon: Icon(
                browse.hasExpanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                size: AppDimens.iconSm,
              ),
              label: Text(
                browse.hasExpanded
                    ? AppStrings.collapseAll
                    : AppStrings.expandAll,
              ),
            ),
        ],
      ),
    );
  }
}

/// 主内容：树或结果列表。
class _Body extends StatelessWidget {
  const _Body({required this.browse});

  final BrowseProvider browse;

  @override
  Widget build(BuildContext context) {
    if (browse.mode == BrowseMode.list) {
      return _ResultList(browse: browse);
    }
    return _CatalogTree(browse: browse);
  }
}

/// 分类树。
class _CatalogTree extends StatelessWidget {
  const _CatalogTree({required this.browse});

  final BrowseProvider browse;

  @override
  Widget build(BuildContext context) {
    final List<BrowseRow> rows = browse.rows;
    return ListView.builder(
      itemCount: rows.length,
      // 行高不固定（教材标题会换行），让 ListView 自行测量。
      itemBuilder: (BuildContext context, int index) {
        final BrowseRow row = rows[index];
        return switch (row) {
          BrowseNodeRow(:final CatalogNode node) => AppTriStateTile(
            depth: node.depth,
            state: browse.selection.stateOf(node.id),
            expandable: node.hasChildren || node.hasBooks,
            expanded: browse.isExpanded(node.id),
            onToggleExpanded: () =>
                context.read<BrowseProvider>().toggleExpanded(node.id),
            onChanged: (bool selected) => context
                .read<BrowseProvider>()
                .setNodeSelected(node.id, selected: selected),
            countLabel: AppStrings.resultCount(node.descendantBookCount),
            label: Text(
              node.label,
              style: TextStyle(fontSize: AppDimens.fontBody),
            ),
          ),
          BrowseBookRow(:final Textbook book) => _BookTile(
            book: book,
            depth: row.depth,
            selected: browse.selection.isSelected(book.id),
            onChanged: (bool selected) => context
                .read<BrowseProvider>()
                .setBookSelected(book.id, selected: selected),
          ),
        };
      },
    );
  }
}

/// 扁平结果列表。
class _ResultList extends StatelessWidget {
  const _ResultList({required this.browse});

  final BrowseProvider browse;

  @override
  Widget build(BuildContext context) {
    final List<Textbook> results = browse.results;
    if (results.isEmpty) {
      return const AppEmptyView(
        icon: Icons.search_off_rounded,
        title: AppStrings.noResultTitle,
        hint: AppStrings.noResultHint,
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final Textbook book = results[index];
        return _BookTile(
          book: book,
          depth: 0,
          // 扁平列表下顺手展示分类路径，否则同名教材分不清是哪一册。
          subtitle: browse.index.categoryPathOf(book),
          selected: browse.selection.isSelected(book.id),
          onChanged: (bool selected) => context
              .read<BrowseProvider>()
              .setBookSelected(book.id, selected: selected),
        );
      },
    );
  }
}

/// 教材行。
class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.depth,
    required this.selected,
    required this.onChanged,
    this.subtitle,
  });

  final Textbook book;
  final int depth;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final String? subtitle = this.subtitle;

    // 整行点击进入详情，勾选交给复选框。
    //
    // 这是文件管理器的通行分工：行是"打开"，勾选框是"选中"。
    // 早先把整行用作勾选，导致想看看这本书讲了什么就必须先勾上它。
    return InkWell(
      onTap: () => context.pushNamed(
        AppRoutes.textbookDetailName,
        pathParameters: <String, String>{'id': book.id},
        extra: book,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimens.gapXs + AppTriStateTile.indentUnit * depth,
          right: AppDimens.gapMd,
          top: AppDimens.gapXs,
          bottom: AppDimens.gapXs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 与分类行对齐：分类行有一个展开箭头 + 间距的宽度。
            SizedBox(width: AppDimens.iconMd + AppDimens.gapXs),
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              onChanged: (bool? value) => onChanged(value ?? false),
            ),
            SizedBox(width: AppDimens.gapXs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    book.title,
                    style: TextStyle(
                      fontSize: AppDimens.fontBodySmall,
                      height: AppDimens.lineHeightNormal,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    SizedBox(height: AppDimens.gapXxs),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppDimens.fontCaption,
                        color: context.secondaryTextColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 批量加入下载队列，并给出明确反馈。
Future<void> _enqueueSelected(
  BuildContext context,
  List<Textbook> books,
) async {
  if (books.isEmpty) {
    return;
  }
  final DownloadProvider downloads = context.read<DownloadProvider>();
  context.showSnackBar(AppStrings.downloadResolving);
  await downloads.enqueue(books);
  if (!context.mounted) {
    return;
  }
  context.showSnackBarWithAction(
    AppStrings.downloadEnqueued(books.length),
    actionLabel: AppStrings.downloadView,
    onAction: () => context.goNamed(AppRoutes.downloadsName),
  );
}

/// 底部勾选操作条。
///
/// 只在有勾选时出现，避免常驻占用空间；出现时把"全选结果""清空""下载"
/// 三个动作放在一起，用户不必回到顶部找入口。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar();

  @override
  Widget build(BuildContext context) {
    final BrowseProvider browse = context.watch<BrowseProvider>();
    if (browse.selection.isEmpty) {
      return const SizedBox.shrink();
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int count = browse.selection.selectedCount;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppDimens.pagePadding,
            vertical: AppDimens.gapXs,
          ),
          // 计数与两个次要按钮放进横向滚动区，主操作（下载选中）始终钉在右侧。
          //
          // 直接用 `Row` 会在窄窗口上溢出——手机的竖屏、或桌面端把窗口拖窄时，
          // 三个按钮加计数文本横向排不下，Flutter 会画一条黄黑条纹并裁掉内容。
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      Text(
                        AppStrings.selectedCount(count),
                        style: TextStyle(
                          fontSize: AppDimens.fontBodySmall,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      SizedBox(width: AppDimens.gapSm),
                      TextButton(
                        onPressed: () =>
                            context.read<BrowseProvider>().toggleAllVisible(),
                        child: const Text(AppStrings.selectAllResults),
                      ),
                      TextButton(
                        onPressed: () =>
                            context.read<BrowseProvider>().clearSelection(),
                        child: const Text(AppStrings.clearSelection),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: AppDimens.gapXs),
              FilledButton(
                onPressed: () =>
                    unawaited(_enqueueSelected(context, browse.selectedBooks)),
                child: const Text(AppStrings.downloadSelected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
