import 'package:flutter/material.dart';

import '../utils/utils.dart';
import '../values/values.dart';

/// 带防抖的搜索框。
///
/// 防抖是必需的：目录有近三千本教材，每敲一个字都重算一次筛选与排序会明显掉帧。
/// 参考项目用的是 150ms，这里给 300ms——中文输入法的候选过程会连发多次
/// `onChanged`，间隔太短等于没防抖。
///
/// [value] 由外部传入而不是自己持有：筛选条件被外部清空时（比如"清空全部"），
/// 输入框里的文字必须跟着消失，否则界面与状态就不一致了。
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    required this.value,
    required this.onChanged,
    super.key,
    this.hint,
    this.delay = const Duration(milliseconds: 300),
  });

  /// 当前关键词。
  final String value;

  /// 防抖后的回调。
  final ValueChanged<String> onChanged;

  /// 占位文案。
  final String? hint;

  /// 防抖时长。
  final Duration delay;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final Debouncer _debouncer = Debouncer(delay: widget.delay);

  @override
  void didUpdateWidget(AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部把值改成了别的（例如"清空全部"），同步到输入框。
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    // Debouncer 持有 Timer，不释放会在页面销毁后仍触发回调。
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // 只为了让清除按钮跟着出现 / 消失
    _debouncer.run(() => widget.onChanged(value));
  }

  void _clear() {
    _debouncer.cancel();
    _controller.clear();
    setState(() {});
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: AppDimens.fontBodySmall),
      decoration: InputDecoration(
        hintText: widget.hint ?? AppStrings.searchHint,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: AppDimens.iconSm,
          color: scheme.onSurfaceVariant,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close_rounded, size: AppDimens.iconSm),
                onPressed: _clear,
                tooltip: AppStrings.cancel,
              ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppDimens.gapMd,
          vertical: AppDimens.gapSm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
