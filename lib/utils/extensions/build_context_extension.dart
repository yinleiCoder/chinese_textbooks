import 'package:flutter/material.dart';

import '../../values/values.dart';

/// [BuildContext] 的语义化快捷访问。
///
/// 目的是把 `Theme.of(context).colorScheme` 这类样板代码收拢到一处：
/// 页面里写 `context.colorScheme`，既短又能保证取值口径一致。
extension BuildContextX on BuildContext {
  // ==================== 主题 ====================

  /// 当前主题数据。
  ThemeData get theme => Theme.of(this);

  /// 当前配色方案。
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// 当前文字样式表。
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// 当前亮度。
  Brightness get brightness => Theme.of(this).brightness;

  /// 是否处于深色模式。
  bool get isDarkMode => brightness == Brightness.dark;

  /// 当前亮度下的次要文字颜色。
  Color get secondaryTextColor =>
      isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

  /// 当前亮度下的成功色。
  Color get successColor => AppColors.successOf(brightness);

  /// 当前亮度下的警告色。
  Color get warningColor => AppColors.warningOf(brightness);

  /// 当前亮度下的信息色。
  Color get infoColor => AppColors.infoOf(brightness);

  // ==================== 屏幕 ====================

  /// 当前屏幕尺寸（逻辑像素）。
  Size get screenSize => MediaQuery.sizeOf(this);

  /// 屏幕宽度。
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// 屏幕高度。
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// 安全区内边距，用于避开刘海与底部手势条。
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);

  /// 底部安全区高度。
  double get bottomSafeArea => MediaQuery.viewPaddingOf(this).bottom;

  /// 键盘弹出高度，为 0 表示键盘未弹出。
  double get keyboardHeight => MediaQuery.viewInsetsOf(this).bottom;

  /// 键盘是否弹出。
  bool get isKeyboardVisible => keyboardHeight > 0;

  /// 系统字体缩放系数，用于判断超大字体的无障碍场景。
  double get textScaleFactor => MediaQuery.textScalerOf(this).scale(1);

  // ==================== 交互 ====================

  /// 收起键盘。
  void unfocus() => FocusScope.of(this).unfocus();

  /// 弹出轻提示。
  ///
  /// 会自动清掉上一条，避免快速连点导致排队等待。
  void showSnackBar(String message, {bool isError = false}) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(this);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colorScheme.error : null,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// 弹出带操作按钮的轻提示。
  ///
  /// 用于"做完了，但你大概想去看看"的场景——例如加入下载队列后给一个
  /// 「查看」入口。只弹一句"已加入队列"而不给去处，用户还得自己找。
  void showSnackBarWithAction(
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    bool isError = false,
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(this);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colorScheme.error : null,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: actionLabel, onPressed: onAction),
        ),
      );
  }

  /// 返回上一页；若已是栈底则什么都不做。
  void pop<T>([T? result]) {
    final NavigatorState navigator = Navigator.of(this);
    if (navigator.canPop()) {
      navigator.pop<T>(result);
    }
  }
}
