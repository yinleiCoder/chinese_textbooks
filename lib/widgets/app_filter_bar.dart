import 'package:flutter/material.dart';

import '../entity/entity.dart';
import '../services/catalog/catalog.dart';
import '../values/values.dart';

/// 紧凑筛选栏：列出已生效的条件，并提供打开筛选面板的入口。
///
/// 为什么不把全部候选项直接铺在页面上：实测「版本」有 113 个选项、
/// 「学科」有 37 个，铺开会吃掉整个屏幕。这里只展示**已选中的**，
/// 选择动作交给 [AppFilterSheet]。
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({
    required this.facets,
    required this.filter,
    required this.onOpenSheet,
    required this.onRemove,
    required this.onClearAll,
    super.key,
  });

  /// 全部可筛选维度。
  final List<CatalogFacet> facets;

  /// 当前筛选条件。
  final CatalogFilter filter;

  /// 打开筛选面板。
  final VoidCallback onOpenSheet;

  /// 移除某个已选条件。
  final void Function(String dimensionId, String tagId) onRemove;

  /// 清空全部筛选。
  final VoidCallback onClearAll;

  /// 已选条件的数量。
  int get selectedCount => filter.selectedByDimension.values.fold(
    0,
    (int sum, Set<String> ids) => sum + ids.length,
  );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Widget> chips = <Widget>[];

    for (final CatalogFacet facet in facets) {
      final Set<String> selected = filter.selectedIn(facet.dimensionId);
      for (final CatalogLevelOption option in facet.options) {
        if (!selected.contains(option.tagId)) {
          continue;
        }
        chips.add(
          InputChip(
            label: Text('${facet.label}：${option.label}'),
            onDeleted: () => onRemove(facet.dimensionId, option.tagId),
            deleteIcon: Icon(Icons.close_rounded, size: AppDimens.iconSm),
            visualDensity: VisualDensity.compact,
          ),
        );
      }
    }

    return SizedBox(
      height: AppDimens.inputHeight,
      child: Row(
        children: <Widget>[
          Expanded(
            child: chips.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppStrings.clearFiltersHint,
                      style: TextStyle(
                        fontSize: AppDimens.fontCaption,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: chips.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(width: AppDimens.gapXs),
                    itemBuilder: (BuildContext context, int index) =>
                        chips[index],
                  ),
          ),
          SizedBox(width: AppDimens.gapXs),
          if (chips.isNotEmpty)
            IconButton(
              onPressed: onClearAll,
              icon: Icon(Icons.filter_alt_off_rounded, size: AppDimens.iconSm),
              tooltip: AppStrings.clearFilters,
              visualDensity: VisualDensity.compact,
            ),
          Badge(
            isLabelVisible: chips.isNotEmpty,
            label: Text('$selectedCount'),
            child: IconButton.filledTonal(
              onPressed: onOpenSheet,
              icon: Icon(Icons.tune_rounded, size: AppDimens.iconSm),
              tooltip: AppStrings.filterTitle,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

/// 筛选面板（底部弹层）。
///
/// 弹层是**独立路由**，位于 `BrowsePage` 之上，因此拿不到页面内的
/// `BrowseProvider`。这里改为：调用方传入初始条件与回调，
/// 弹层内部用局部状态维护一份副本并即时回调——两边始终保持一致。
class AppFilterSheet extends StatefulWidget {
  const AppFilterSheet({
    required this.facets,
    required this.initialFilter,
    required this.onChanged,
    super.key,
  });

  /// 全部可筛选维度。
  final List<CatalogFacet> facets;

  /// 打开时的筛选条件。
  final CatalogFilter initialFilter;

  /// 条件变化时的回调，**每次勾选都会调用**，不需要等用户点确定。
  final ValueChanged<CatalogFilter> onChanged;

  @override
  State<AppFilterSheet> createState() => _AppFilterSheetState();
}

class _AppFilterSheetState extends State<AppFilterSheet> {
  late CatalogFilter _filter = widget.initialFilter;

  void _toggle(String dimensionId, String tagId) {
    setState(() => _filter = _filter.toggle(dimensionId, tagId));
    widget.onChanged(_filter);
  }

  void _clearDimension(String dimensionId) {
    setState(() => _filter = _filter.clearDimension(dimensionId));
    widget.onChanged(_filter);
  }

  void _clearAll() {
    setState(() => _filter = _filter.cleared());
    widget.onChanged(_filter);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) {
        return Column(
          children: <Widget>[
            _header(context),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: EdgeInsets.symmetric(vertical: AppDimens.gapSm),
                itemCount: widget.facets.length,
                itemBuilder: (BuildContext context, int index) =>
                    _facetSection(widget.facets[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppDimens.pagePadding,
        vertical: AppDimens.gapSm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            AppStrings.filterTitle,
            style: TextStyle(
              fontSize: AppDimens.fontSubtitle,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _filter.isEmpty ? null : _clearAll,
            child: const Text(AppStrings.clearFilters),
          ),
        ],
      ),
    );
  }

  Widget _facetSection(CatalogFacet facet) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Set<String> selected = _filter.selectedIn(facet.dimensionId);

    return Padding(
      padding: EdgeInsets.only(bottom: AppDimens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppDimens.pagePadding,
              vertical: AppDimens.gapXs,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  facet.label,
                  style: TextStyle(
                    fontSize: AppDimens.fontBodySmall,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                SizedBox(width: AppDimens.gapXs),
                Text(
                  AppStrings.resultCount(facet.options.length),
                  style: TextStyle(
                    fontSize: AppDimens.fontCaption,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (selected.isNotEmpty) ...<Widget>[
                  const Spacer(),
                  TextButton(
                    onPressed: () => _clearDimension(facet.dimensionId),
                    child: const Text(AppStrings.clearDimension),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
            child: Wrap(
              spacing: AppDimens.gapXs,
              runSpacing: AppDimens.gapXxs,
              children: <Widget>[
                for (final CatalogLevelOption option in facet.options)
                  FilterChip(
                    label: Text('${option.label}（${option.bookCount}）'),
                    selected: selected.contains(option.tagId),
                    onSelected: (_) => _toggle(facet.dimensionId, option.tagId),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
