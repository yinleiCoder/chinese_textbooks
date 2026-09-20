import 'package:chinese_textbooks/utils/utils.dart';
import 'package:chinese_textbooks/values/values.dart';
import 'package:chinese_textbooks/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppErrorView] 的核心约定：**只给可重试的失败配重试按钮**。
///
/// 这是本组件存在的理由——把"要不要给重试入口"的判断从各个页面收敛到一处，
/// 因此值得用测试把这条规则钉住。
void main() {
  /// 组件依赖 `AppDimens` 中的屏幕适配值，必须包在 `ScreenUtilInit` 里才能渲染。
  Future<void> pumpView(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      ScreenUtilInit(
        designSize: AppConfig.designSize,
        builder: (BuildContext context, Widget? _) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  group('AppErrorView 的重试入口', () {
    testWidgets('网络失败：展示文案与重试按钮，点击触发回调', (WidgetTester tester) async {
      int retryCount = 0;
      await pumpView(
        tester,
        AppErrorView.fromFailure(
          const NetworkFailure(message: '网络连接不可用'),
          onRetry: () => retryCount++,
        ),
      );

      expect(find.text('网络连接不可用'), findsOneWidget);
      expect(find.text(AppStrings.retry), findsOneWidget);

      await tester.tap(find.text(AppStrings.retry));
      await tester.pump();

      expect(retryCount, 1);
    });

    testWidgets('服务端 5xx：可重试', (WidgetTester tester) async {
      await pumpView(
        tester,
        AppErrorView.fromFailure(
          const ServerFailure(message: '服务器开小差了', statusCode: 500),
          onRetry: () {},
        ),
      );

      expect(find.text(AppStrings.retry), findsOneWidget);
    });

    testWidgets('参数错误：不可重试，不展示重试按钮', (WidgetTester tester) async {
      await pumpView(
        tester,
        AppErrorView.fromFailure(
          const ClientFailure(message: '请求有误', statusCode: 400),
          onRetry: () {},
        ),
      );

      expect(find.text('请求有误'), findsOneWidget);
      expect(
        find.text(AppStrings.retry),
        findsNothing,
        reason: '4xx 重试多少次结果都一样，不应给出重试入口',
      );
    });

    testWidgets('解析失败：不可重试', (WidgetTester tester) async {
      await pumpView(
        tester,
        AppErrorView.fromFailure(
          const ParseFailure(message: '数据格式异常'),
          onRetry: () {},
        ),
      );

      expect(find.text(AppStrings.retry), findsNothing);
    });

    testWidgets('未传 onRetry 时不展示重试按钮', (WidgetTester tester) async {
      await pumpView(
        tester,
        AppErrorView.fromFailure(const NetworkFailure(message: '网络连接不可用')),
      );

      expect(find.text(AppStrings.retry), findsNothing);
    });
  });
}
