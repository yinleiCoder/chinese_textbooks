import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../entity/entity.dart';
import '../../values/values.dart';

/// 平台请求签名器（`X-ND-AUTH`）。
///
/// 对应官网 UC SDK 的 `getAuthHeader`：**每次请求现算，绝不复用抓包里的整段头**。
/// 签名原文包含完整路径，同一个头换一个 URL 就失效。
///
/// ## 格式
///
/// ```
/// nonce     = "{服务器毫秒时间戳}:{8 位随机串}"
/// 签名原文  = "{nonce}\n{METHOD}\n{解码后的 path}{?query}\n{hostname}\n"   ← 末尾必须有换行
/// mac       = Base64(HMAC-SHA256(mac_key, 签名原文))
/// 头值      = MAC id="{access_token}",nonce="{nonce}",mac="{mac}"
/// ```
///
/// ## 三个必须照抄、不能"顺手修正"的细节
///
/// 1. **`unquote(path)` 之后再签名，但请求发编码后的路径。** 教材文件名里有中文
///    和 `•`，HAR 里抓到的编码路径与官网算出的 mac 对不上，解码后才一致。
///    这两个表示必须严格区分——签名用解码后的，发请求用编码后的。
/// 2. **hostname 不含端口，且末尾那个换行不能省。** 服务端按行切分四段。
/// 3. **nonce 后缀的下标上界是 35，不是字符表长度 36。**
///    官网写的是 `Math.ceil(35 * random())`，因此 `'0'` 几乎抽不到。
///    这是要复刻的行为，不是 bug。
final class NdAuthSigner {
  NdAuthSigner({Random? random, DateTime Function()? clock})
    : _random = random ?? Random(),
      _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;

  /// 生成本次请求的 nonce。
  ///
  /// [diff] 是本地时钟相对平台服务器的毫秒差，由凭据携带。
  /// nonce 必须每次不同：服务端会做重放检查。
  String issueNonce(int diff) {
    final int millis = _clock().millisecondsSinceEpoch + diff;
    final StringBuffer suffix = StringBuffer();
    for (int i = 0; i < NdConfig.nonceSuffixLength; i++) {
      // ceil(35 * r)：r 取 [0,1)，结果落在 [0,35]。
      // 只有 r 恰好为 0 时才会取到下标 0（字符 '0'），概率可以忽略——
      // 这正是官网的行为，别改成 36。
      final int index = (NdConfig.nonceIndexBound * _random.nextDouble())
          .ceil();
      suffix.write(NdConfig.nonceAlphabet[index]);
    }
    return '$millis:$suffix';
  }

  /// 组装完整的 `X-ND-AUTH` 头值。
  ///
  /// 凭据缺失或没有 `mac_key` 时退回占位头——它对公开的 JSON 接口无害
  /// （那些接口根本不校验），但私有资源会拿到 401。
  ///
  /// [nonce] 只用于测试：生产路径必须让它现算，否则同一个 nonce 复用会被
  /// 服务端的重放检查拒绝。可注入才能对固定输入做**已知答案测试**。
  String headerValue({
    required NdCredential? credential,
    required String method,
    required Uri url,
    String? nonce,
  }) {
    final String tokenId = credential?.accessToken ?? '0';
    final String? macKey = credential?.macKey;
    if (macKey == null || macKey.isEmpty) {
      return 'MAC id="$tokenId",nonce="0",mac="0"';
    }

    final String effectiveNonce = nonce ?? issueNonce(credential?.diff ?? 0);
    final String mac = signMac(
      buildSigningString(nonce: effectiveNonce, method: method, url: url),
      macKey,
    );
    return 'MAC id="$tokenId",nonce="$effectiveNonce",mac="$mac"';
  }

  /// 计算 mac：`Base64(HMAC-SHA256(mac_key, 签名原文))`。
  ///
  /// 公开是为了让测试能对同一个原文独立复算。
  static String signMac(String text, String macKey) {
    final Hmac hmac = Hmac(sha256, utf8.encode(macKey));
    return base64.encode(hmac.convert(utf8.encode(text)).bytes);
  }

  /// 构造 HMAC 的原文。
  ///
  /// 抽成静态方法是为了能对**固定输入**做已知答案测试——
  /// 这段字符串的换行位置错一个字节，签名就会被服务端拒绝，
  /// 而错误信息只会是一个笼统的 401。
  static String buildSigningString({
    required String nonce,
    required String method,
    required Uri url,
  }) {
    // Uri.path 保留百分号编码，这里要的是解码后的原文。
    // 不能用 pathSegments：它会丢掉路径分隔符的编码细节。
    final String path = Uri.decodeComponent(url.path);
    final String pathAndQuery = url.hasQuery ? '$path?${url.query}' : path;
    return '$nonce\n${method.toUpperCase()}\n$pathAndQuery\n${url.host}\n';
  }
}
