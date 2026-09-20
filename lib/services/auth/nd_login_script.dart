import 'dart:convert';

import '../../entity/entity.dart';

/// 从平台页面的 localStorage 里取登录凭据。
///
/// ## 为什么在 WebView 里读，而不是让用户粘贴
///
/// 参考项目要求用户打开浏览器控制台、手抄一段 JSON 再粘贴回来，
/// 其 issue 里反复有人卡在 Chrome 的"允许粘贴"拦截上。
/// 既然应用已经内嵌了官方登录页，用户登录完凭据就在同一个 localStorage 里，
/// 直接读出来即可——**用的是用户自己登录产生的凭据**，没有任何伪造。
abstract final class NdLoginScript {
  /// 平台存放登录凭据的键名格式。
  ///
  /// 登录后 localStorage 里会出现若干 `ND_UC_AUTH-*` 键，**只有以 `token`
  /// 结尾的那个才含凭据**；同前缀的 `sdk_cache` 是账号资料缓存，
  /// 读错了只会得到 `null`（参考项目的 issue #89 就踩过这个坑）。
  static final RegExp credentialKeyPattern = RegExp(
    r'^ND_UC_AUTH-[^&]+&[^&]+&token$',
  );

  /// 在页面里执行的取凭据脚本。
  ///
  /// 返回一个 JSON 字符串而不是裸值：字符串返回值经平台通道传回来后，
  /// 无法区分"没找到"与"凭据恰好是空串"，包一层对象就没有歧义了。
  static const String probeScript = r'''
(function () {
  try {
    var pattern = /^ND_UC_AUTH-[^&]+&[^&]+&token$/;
    for (var i = 0; i < localStorage.length; i++) {
      var key = localStorage.key(i);
      if (key && pattern.test(key)) {
        return JSON.stringify({
          found: true,
          key: key,
          value: localStorage.getItem(key)
        });
      }
    }
    return JSON.stringify({ found: false });
  } catch (e) {
    return JSON.stringify({ found: false, error: String(e) });
  }
})()
''';

  /// 解析脚本的返回值。
  ///
  /// [raw] 是 `evaluateJavascript` 的返回，可能是 JSON 字符串，
  /// 也可能是平台已经解码好的对象（不同平台实现不一致）。
  static CredentialProbe parseProbe(Object? raw) {
    final Object? decoded = _decode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const CredentialProbe.notFound();
    }
    final Object? error = decoded['error'];
    if (error is String) {
      return CredentialProbe.failed(error);
    }
    final Object? value = decoded['value'];
    if (decoded['found'] != true || value is! String) {
      return const CredentialProbe.notFound();
    }
    return CredentialProbe.found(NdCredential.tryParseLocalStorageValue(value));
  }

  static Object? _decode(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is! String || raw.isEmpty || raw == 'null') {
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}

/// 一次取凭据探测的结果。
final class CredentialProbe {
  /// 已找到并解析成功。
  const CredentialProbe.found(this.credential) : isFound = true, error = null;

  /// 还没找到——用户尚未登录，或登录还没完成。
  ///
  /// **这不是错误**，调用方应当继续轮询。
  const CredentialProbe.notFound()
    : isFound = false,
      credential = null,
      error = null;

  /// 页面里抛了异常，通常是页面还没加载完。
  const CredentialProbe.failed(this.error) : isFound = false, credential = null;

  /// 是否找到了凭据。
  final bool isFound;

  /// 解析出的凭据；找到了但格式不对时为 `null`。
  final NdCredential? credential;

  /// 页面侧的异常信息。
  final String? error;

  /// 是否拿到了可用的凭据（**有 mac_key 才算可用**）。
  ///
  /// 只有 `access_token` 没有 `mac_key` 的形态能读公开接口，
  /// 但下不了需要签名的教材，不能当作登录成功。
  bool get isUsable => credential != null && credential!.canSign;
}
