import 'package:flutter/material.dart';

import '../services/catalog/catalog.dart';
import '../values/values.dart';

/// 三态复选框行。
///
/// 分类树的核心控件：分类节点的勾选状态由其后代推导，因此有三种取值——
/// 未选、半选、全选。半选态用 `Checkbox(value: null)` 表达，
/// 这是 Material 的原生约定，不要自己画一个"半选图标"。
///
/// [depth] 决定左缩进，让层级一眼可辨；[trailing] 用来放"共 N 本"这类计数。
class AppTriStateTile extends StatelessWidget {
  const AppTriStateTile({
    required this.state,
    required this.onChanged,
    super.key,
    this.label,
    this.depth = 0,
    this.expandable = false,
    this.expanded = false,
    this.onToggleExpanded,
    this.trailing,
    this.countLabel,
    this.padding,
  });

  /// 当前三态。
  final SelectionState state;

  /// 勾选回调，参数是"目标状态"。
  ///
  /// 半选时点一下变成全选——这是三态树的通行交互：
  /// 用户看到半选，想要的通常是"把这些都选上"，而不是"全取消"。
  final ValueChanged<bool> onChanged;

  /// 标题。为空时只渲染复选框（用于纯选择场景）。
  final Widget? label;

  /// 层级，从 0 起。
  final int depth;

  /// 是否有子节点。
  final bool expandable;

  /// 是否已展开。
  final bool expanded;

  /// 展开 / 收起回调。
  final VoidCallback? onToggleExpanded;

  /// 右侧附加内容。
  final Widget? trailing;

  /// 计数文案，如「32 本」。
  final String? countLabel;

  /// 自定义内边距。
  final EdgeInsetsGeometry? padding;

  /// 每层的缩进量。
  static double get indentUnit => AppDimens.gapLg;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? countLabel = this.countLabel;
    final Widget? trailing = this.trailing;

    // 半选 → 点一下全选；其余 → 取反。
    final bool targetValue = state != SelectionState.all;

    return InkWell(
      onTap: () => onChanged(targetValue),
      child: Padding(
        padding:
            padding ??
            EdgeInsets.only(
              left: AppDimens.gapXs + indentUnit * depth,
              right: AppDimens.gapMd,
              top: AppDimens.gapXxs,
              bottom: AppDimens.gapXxs,
            ),
        child: Row(
          children: <Widget>[
            if (expandable)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: AppDimens.iconMd,
                  height: AppDimens.iconMd,
                ),
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: AppDimens.iconSm,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: onToggleExpanded,
                tooltip: expanded ? AppStrings.collapse : AppStrings.expand,
              )
            else
              SizedBox(width: AppDimens.iconMd),
            SizedBox(width: AppDimens.gapXs),
            Checkbox(
              value: switch (state) {
                SelectionState.none => false,
                SelectionState.partial => null,
                SelectionState.all => true,
              },
              tristate: true,
              visualDensity: VisualDensity.compact,
              onChanged: (bool? _) => onChanged(targetValue),
            ),
            SizedBox(width: AppDimens.gapXs),
            Expanded(child: label ?? const SizedBox.shrink()),
            if (countLabel != null) ...<Widget>[
              SizedBox(width: AppDimens.gapXs),
              Text(
                countLabel,
                style: TextStyle(
                  fontSize: AppDimens.fontCaption,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            ?trailing,
          ],
        ),
      ),
    );
  }
}
