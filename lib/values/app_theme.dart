import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// 主题构建器。
///
/// 设计约束：
/// - 只暴露 [light] / [dark] 两个入口，[ThemeMode] 的切换由 `ThemeProvider` 决定；
/// - 所有尺寸与字号统一取自 [AppDimens]，主题内不出现魔法数字；
/// - 组件级样式集中在 [_build] 里一次性下发，页面里不再逐个覆写，
///   避免同类控件在不同页面长得不一样。
abstract final class AppTheme {
  /// 浅色主题。
  static ThemeData get light => _build(Brightness.light);

  /// 深色主题。
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );

    final Color surface = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final Color divider = isDark
        ? AppColors.darkDivider
        : AppColors.lightDivider;
    final Color secondaryText = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      dividerColor: divider,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(scheme),
      appBarTheme: _appBarTheme(scheme, surface, isDark),
      cardTheme: _cardTheme(surface, divider),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: AppDimens.dividerThickness,
        space: AppDimens.dividerThickness,
      ),
      elevatedButtonTheme: _elevatedButtonTheme(),
      filledButtonTheme: _filledButtonTheme(),
      outlinedButtonTheme: _outlinedButtonTheme(scheme),
      textButtonTheme: _textButtonTheme(scheme),
      inputDecorationTheme: _inputDecorationTheme(scheme, surface, divider),
      listTileTheme: _listTileTheme(secondaryText),
      navigationBarTheme: _navigationBarTheme(scheme, surface),
      bottomNavigationBarTheme: _bottomNavigationBarTheme(
        scheme,
        surface,
        secondaryText,
      ),
      dialogTheme: _dialogTheme(scheme, surface),
      bottomSheetTheme: _bottomSheetTheme(surface),
      snackBarTheme: _snackBarTheme(scheme, isDark),
      chipTheme: _chipTheme(scheme, surface),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: AppDimens.fontCaption,
        ),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
      ),
      splashColor: scheme.primary.withValues(alpha: 0.08),
      highlightColor: scheme.primary.withValues(alpha: 0.04),
    );
  }

  // ==================== 文字 ====================

  static TextTheme _textTheme(ColorScheme scheme) {
    // 每个样式都要有颜色。留空的话 Text 会去合并外层 DefaultTextStyle，
    // 而它也来自这套主题——两边都没有颜色时文字就不渲染。
    final Color primaryText = scheme.onSurface;
    final Color secondaryText = scheme.onSurfaceVariant;

    TextStyle style(double size, FontWeight weight, {Color? color}) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color ?? primaryText,
          height: AppDimens.lineHeightNormal,
        );

    return TextTheme(
      displayLarge: style(
        AppDimens.fontDisplay,
        FontWeight.w700,
      ).copyWith(height: AppDimens.lineHeightTight),
      displayMedium: style(
        AppDimens.fontHeadline,
        FontWeight.w700,
      ).copyWith(height: AppDimens.lineHeightTight),
      displaySmall: style(
        AppDimens.fontTitle,
        FontWeight.w700,
      ).copyWith(height: AppDimens.lineHeightTight),
      headlineMedium: style(
        AppDimens.fontSubtitle,
        FontWeight.w700,
      ).copyWith(height: AppDimens.lineHeightTight),
      titleLarge: style(AppDimens.fontSubtitle, FontWeight.w700),
      titleMedium: style(AppDimens.fontBody, FontWeight.w700),
      titleSmall: style(AppDimens.fontBodySmall, FontWeight.w700),
      bodyLarge: style(AppDimens.fontBody, FontWeight.w400),
      bodyMedium: style(AppDimens.fontBodySmall, FontWeight.w400),
      bodySmall: style(
        AppDimens.fontCaption,
        FontWeight.w400,
        color: secondaryText,
      ),
      labelLarge: style(AppDimens.fontBody, FontWeight.w700),
      labelMedium: style(AppDimens.fontBodySmall, FontWeight.w700),
      labelSmall: style(
        AppDimens.fontCaption,
        FontWeight.w700,
        color: secondaryText,
      ),
    );
  }

  // ==================== 组件 ====================

  static AppBarTheme _appBarTheme(
    ColorScheme scheme,
    Color surface,
    bool isDark,
  ) {
    return AppBarTheme(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: AppDimens.appBarHeight,
      titleTextStyle: TextStyle(
        fontSize: AppDimens.fontSubtitle,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(size: AppDimens.iconMd, color: scheme.onSurface),
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    );
  }

  static CardThemeData _cardTheme(Color surface, Color divider) {
    return CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        side: BorderSide(color: divider, width: AppDimens.dividerThickness),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: Size(0, AppDimens.buttonHeight),
        padding: EdgeInsets.symmetric(horizontal: AppDimens.gapLg),
        textStyle: TextStyle(
          fontSize: AppDimens.fontBody,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, AppDimens.buttonHeight),
        padding: EdgeInsets.symmetric(horizontal: AppDimens.gapLg),
        textStyle: TextStyle(
          fontSize: AppDimens.fontBody,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme scheme) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, AppDimens.buttonHeight),
        padding: EdgeInsets.symmetric(horizontal: AppDimens.gapLg),
        foregroundColor: scheme.primary,
        textStyle: TextStyle(
          fontSize: AppDimens.fontBody,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(
          color: scheme.outlineVariant,
          width: AppDimens.dividerThickness,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(ColorScheme scheme) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        padding: EdgeInsets.symmetric(
          horizontal: AppDimens.gapSm,
          vertical: AppDimens.gapXs,
        ),
        textStyle: TextStyle(
          fontSize: AppDimens.fontBodySmall,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(
    ColorScheme scheme,
    Color surface,
    Color divider,
  ) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      borderSide: BorderSide(color: color, width: width),
    );

    return InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppDimens.gapMd,
        vertical: AppDimens.gapSm,
      ),
      hintStyle: TextStyle(
        fontSize: AppDimens.fontBodySmall,
        color: scheme.onSurfaceVariant,
      ),
      border: border(divider, AppDimens.dividerThickness),
      enabledBorder: border(divider, AppDimens.dividerThickness),
      focusedBorder: border(scheme.primary, 1.5),
      errorBorder: border(scheme.error, AppDimens.dividerThickness),
      focusedErrorBorder: border(scheme.error, 1.5),
      errorStyle: TextStyle(
        fontSize: AppDimens.fontCaption,
        color: scheme.error,
      ),
    );
  }

  static ListTileThemeData _listTileTheme(Color secondaryText) {
    return ListTileThemeData(
      minVerticalPadding: AppDimens.gapSm,
      contentPadding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      titleTextStyle: TextStyle(
        fontSize: AppDimens.fontBody,
        fontWeight: FontWeight.w700,
        color: secondaryText,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: AppDimens.fontBodySmall,
        color: secondaryText,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
    );
  }

  static NavigationBarThemeData _navigationBarTheme(
    ColorScheme scheme,
    Color surface,
  ) {
    return NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: AppDimens.listItemHeight,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => TextStyle(
          fontSize: AppDimens.fontCaption,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => IconThemeData(
          size: AppDimens.iconMd,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static BottomNavigationBarThemeData _bottomNavigationBarTheme(
    ColorScheme scheme,
    Color surface,
    Color secondaryText,
  ) {
    return BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: scheme.primary,
      unselectedItemColor: secondaryText,
      selectedLabelStyle: TextStyle(fontSize: AppDimens.fontCaption),
      unselectedLabelStyle: TextStyle(fontSize: AppDimens.fontCaption),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    );
  }

  static DialogThemeData _dialogTheme(ColorScheme scheme, Color surface) {
    return DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      // **必须显式给 color。** 只给字号字重的话，Text 会去合并外层的
      // DefaultTextStyle，而后者同样没有颜色，结果是弹窗里
      // 只剩按钮可见、标题与正文不渲染。
      titleTextStyle: TextStyle(
        fontSize: AppDimens.fontSubtitle,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontSize: AppDimens.fontBodySmall,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(Color surface) {
    return BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusLg),
        ),
      ),
    );
  }

  static SnackBarThemeData _snackBarTheme(ColorScheme scheme, bool isDark) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        fontSize: AppDimens.fontBodySmall,
        color: scheme.onInverseSurface,
      ),
      actionTextColor: isDark ? scheme.inversePrimary : scheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      insetPadding: EdgeInsets.all(AppDimens.pagePadding),
    );
  }

  static ChipThemeData _chipTheme(ColorScheme scheme, Color surface) {
    return ChipThemeData(
      backgroundColor: surface,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(
        color: scheme.outlineVariant,
        width: AppDimens.dividerThickness,
      ),
      labelStyle: TextStyle(
        fontSize: AppDimens.fontCaption,
        color: scheme.onSurface,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppDimens.gapXs,
        vertical: AppDimens.gapXxs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
    );
  }
}
