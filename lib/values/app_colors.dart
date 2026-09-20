import 'package:flutter/material.dart';

/// 应用调色板。
///
/// 主色与中性色由 Material 3 的 [ColorScheme.fromSeed] 派生，
/// 这里只定义**色板种子**与 **M3 未覆盖的语义色**（成功 / 警告 / 信息），
/// 避免主题里出现零散的硬编码颜色。
abstract final class AppColors {
  /// 品牌种子色：黛蓝，取"青出于蓝"的书面感，契合语文教材的调性。
  static const Color seed = Color(0xFF2B5C8A);

  // ==================== 语义色 ====================

  /// 成功：完成学习任务、答题正确。
  static const Color success = Color(0xFF2E7D5B);

  /// 警告：需要留意但未阻塞的提示。
  static const Color warning = Color(0xFFB8791B);

  /// 信息：中性提示。
  static const Color info = Color(0xFF3A6EA5);

  // ==================== 亮色模式 ====================

  /// 亮色模式下的页面背景。
  static const Color lightBackground = Color(0xFFF7F8FA);

  /// 亮色模式下的卡片背景。
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// 亮色模式下的分割线。
  static const Color lightDivider = Color(0xFFE6E8EC);

  /// 亮色模式下的次要文字。
  static const Color lightTextSecondary = Color(0xFF5F6672);

  // ==================== 暗色模式 ====================

  /// 暗色模式下的页面背景。
  static const Color darkBackground = Color(0xFF121417);

  /// 暗色模式下的卡片背景。
  static const Color darkSurface = Color(0xFF1C1F24);

  /// 暗色模式下的分割线。
  static const Color darkDivider = Color(0xFF2C3138);

  /// 暗色模式下的次要文字。
  static const Color darkTextSecondary = Color(0xFFA5ACB8);

  /// 按亮度返回对应的语义色，供自定义组件统一取色。
  ///
  /// 之所以不用 `Theme.of(context)`，是因为语义色不属于 [ColorScheme]，
  /// 这里按亮度直接给出，避免各处重复写 `isDark ? a : b`。
  static Color successOf(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF5FBF90) : success;

  /// 警告色（按亮度）。
  static Color warningOf(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFFE0A952) : warning;

  /// 信息色（按亮度）。
  static Color infoOf(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF7FA9D8) : info;
}
