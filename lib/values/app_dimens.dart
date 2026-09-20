import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'app_config.dart';

/// 尺寸与字号规范。
///
/// 所有取值都经过 [_u] / [_sp] 换算：**移动端**按 `AppConfig.designSize`
/// 等比适配，**桌面端原样返回**（1 设计单位 = 1 逻辑像素）。
///
/// 为什么桌面端不缩放：设计稿是 360×690 的手机尺寸，桌面窗口常有 1500
/// 逻辑像素宽，按宽度等比缩放会到 4 倍以上，字被放大到离谱。
/// 详见 `AppConfig.scaleUi` 的注释。
///
/// 移动端换算规则（桌面端一律原样返回）：
/// - 间距与控件尺寸走 `.w`，按宽度等比；
/// - 圆角、图标边长走 `.r`，按宽高较小值等比，保证正方形不变形；
/// - 字号走 `.sp`。
///
/// 因为换算依赖 [ScreenUtil] 的运行时状态，这里统一使用 getter 而非 const 常量。
abstract final class AppDimens {
  /// 长度换算。
  static double _u(double value) => AppConfig.scaleUi ? value.w : value;

  /// 字号换算。
  static double _sp(double value) => AppConfig.scaleUi ? value.sp : value;

  // ==================== 间距 ====================

  /// 4dp：图标与文字之间的极小间隙。
  static double get gapXxs => _u(4);

  /// 8dp：紧凑间距。
  static double get gapXs => _u(8);

  /// 12dp：列表项内部间距。
  static double get gapSm => _u(12);

  /// 16dp：常规间距。
  static double get gapMd => _u(16);

  /// 24dp：区块之间的间距。
  static double get gapLg => _u(24);

  /// 32dp：大区块分隔。
  static double get gapXl => _u(32);

  // ==================== 页面 ====================

  /// 页面左右安全边距。
  static double get pagePadding => _u(20);

  /// 正文内容的最大宽度。
  ///
  /// 桌面窗口可以很宽，但一行文字超过约 60 个字符后就难以阅读，
  /// 整页提示也会显得空旷。居中 + 限宽是宽屏下的通行做法。
  static double get contentMaxWidth => 480;

  /// 页面顶部边距（不含 AppBar）。
  static double get pagePaddingTop => _u(16);

  /// 卡片内边距。
  static double get cardPadding => _u(16);

  // ==================== 圆角 ====================

  /// 小圆角：标签、输入框。
  static double get radiusSm => _u(8);

  /// 常规圆角：卡片、弹窗。
  static double get radiusMd => _u(12);

  /// 大圆角：底部弹层、大卡片。
  static double get radiusLg => _u(16);

  /// 胶囊圆角：按钮、Chip。
  static double get radiusPill => 999;

  // ==================== 控件尺寸 ====================

  /// 主要按钮高度。
  static double get buttonHeight => _u(48);

  /// 输入框高度。
  static double get inputHeight => _u(48);

  /// 列表项最小高度。
  static double get listItemHeight => _u(56);

  /// 小图标边长。
  static double get iconSm => _u(16);

  /// 常规图标边长。
  static double get iconMd => _u(24);

  /// 大图标边长。
  static double get iconLg => _u(32);

  /// 头像边长。
  static double get avatar => _u(40);

  /// 空态 / 错误态的大图标。
  static double get iconXl => _u(64);

  /// 整页提示的大图标（目录准备页、404 页）。
  static double get iconDisplay => _u(72);

  /// 欢迎页的巨型图标。
  static double get iconHero => _u(80);

  /// 细进度条的高度。
  static double get progressHeight => _u(6);

  /// 分割线厚度（不随屏幕缩放，保持 1 物理像素观感）。
  static const double dividerThickness = 0.5;

  /// AppBar 高度。
  static double get appBarHeight => _u(48);

  // ==================== 字号 ====================

  /// 辅助说明文字。
  static double get fontCaption => _sp(12);

  /// 正文小号。
  static double get fontBodySmall => _sp(14);

  /// 正文。
  static double get fontBody => _sp(16);

  /// 小标题。
  static double get fontSubtitle => _sp(18);

  /// 标题。
  static double get fontTitle => _sp(20);

  /// 大标题。
  static double get fontHeadline => _sp(24);

  /// 超大标题。
  static double get fontDisplay => _sp(32);

  // ==================== 行高 ====================

  /// 紧凑行高，适用于标题。
  static const double lineHeightTight = 1.3;

  /// 常规行高，适用于正文。
  static const double lineHeightNormal = 1.5;

  /// 宽松行高，适用于教材原文等长文本阅读场景。
  static const double lineHeightLoose = 1.8;
}
