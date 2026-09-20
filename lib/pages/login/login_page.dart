import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../services/auth/auth.dart';
import '../../values/values.dart';
import '../../widgets/widgets.dart';

/// 登录页。
///
/// 内嵌平台**官方登录页**，用户在页面里正常登录；登录完成后凭据会出现在
/// 该页面的 localStorage 里，应用读出来存进安全存储。
///
/// 这就是"用用户自己的账号登录"——不伪造、不破解、不共享任何凭据。
///
/// ## 为什么要轮询而不是只读一次
///
/// 平台是单页应用：`onLoadStop` 触发时登录往往还没完成，登录成功后
/// 页面也**不会重新加载**。只在加载完成时读一次必然读不到，
/// 所以要在页面稳定后持续探测，直到拿到凭据或用户主动关闭。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /// 探测间隔。
  ///
  /// 取 1.2 秒：比这更密只是白跑 JS，更疏则用户会觉得"登录了却半天没反应"。
  static const Duration _probeInterval = Duration(milliseconds: 1200);

  InAppWebViewController? _controller;
  bool _pageReady = false;
  Timer? _timer;
  bool _handled = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 页面加载完成后开始轮询。
  void _startProbing() {
    _timer?.cancel();
    _timer = Timer.periodic(_probeInterval, (_) => unawaited(_probe()));
  }

  /// 探测一次。
  Future<void> _probe() async {
    if (_handled) {
      return;
    }
    final InAppWebViewController? controller = _controller;
    if (controller == null) {
      return;
    }

    final Object? raw;
    try {
      raw = await controller.evaluateJavascript(
        source: NdLoginScript.probeScript,
      );
    } on Object catch (_) {
      // 页面切换过程中执行脚本会失败，属于正常现象，等下一轮。
      return;
    }

    final CredentialProbe probe = NdLoginScript.parseProbe(raw);
    if (!probe.isUsable) {
      // 没找到或只有 access_token 没有 mac_key——继续等用户完成登录。
      return;
    }

    _handled = true;
    _timer?.cancel();

    if (!mounted) {
      return;
    }
    await context.read<AuthSessionProvider>().save(probe.credential!);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.loginTitle),
        actions: <Widget>[
          TextButton(
            // 手动触发一次探测：SPA 的登录完成时点不确定，
            // 给用户一个"我登好了"的按钮比让他干等更可靠。
            onPressed: () => unawaited(_probe()),
            child: const Text(AppStrings.loginDone),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Material(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
                vertical: AppDimens.gapSm,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: AppDimens.iconSm,
                    color: scheme.onSurfaceVariant,
                  ),
                  SizedBox(width: AppDimens.gapXs),
                  Expanded(
                    child: Text(
                      AppStrings.loginHint,
                      style: TextStyle(
                        fontSize: AppDimens.fontCaption,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(NdConfig.siteHome)),
                  onWebViewCreated: (InAppWebViewController controller) {
                    _controller = controller;
                  },
                  onLoadStop: (_, _) {
                    if (!_pageReady) {
                      setState(() => _pageReady = true);
                    }
                    _startProbing();
                  },
                ),
                // 内置浏览器在 Windows 上首次创建要加载 WebView2 运行时，
                // 实测要十几秒。没有这个提示，用户会以为页面坏了。
                if (!_pageReady)
                  const ColoredBox(
                    color: Colors.white,
                    child: AppLoadingView(
                      message: AppStrings.loginInitializing,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
