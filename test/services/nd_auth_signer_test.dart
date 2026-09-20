import 'dart:math';

import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/services/http/nd_auth_signer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 签名的**已知答案测试**。
///
/// 为什么值得这么写：这段签名错一个字节，服务端只会回一个笼统的 401，
/// 既不会说"你的换行位置错了"，也不会说"hostname 不该带端口"。
/// 期望值是用同样输入在 Python 里独立算出来的，不是拿实现反推的——
/// 后者只能证明"代码没变"，证明不了"代码对"。
void main() {
  const String macKey = 'test-mac-key';
  const String accessToken = 'test-access-token';
  const String nonce = '1700000000000:ABCDEFGH';
  const String host = 'r1-ndr-private.ykt.cbern.com.cn';

  /// 含中文与 `•` 的教材路径，编码后的形态。
  const String encodedPath =
      '/edu_product/esp/assets/abc.pkg/'
      '%E4%B9%89%E5%8A%A1%E6%95%99%E8%82%B2%E6%95%99%E7%A7%91%E4%B9%A6'
      '%E2%80%A2%E8%AF%AD%E6%96%87.pdf';

  /// 解码后的同一路径。
  const String decodedPath =
      '/edu_product/esp/assets/abc.pkg/义务教育教科书•语文.pdf';

  group('签名原文', () {
    test('四段以换行分隔，末尾也有换行', () {
      final String text = NdAuthSigner.buildSigningString(
        nonce: nonce,
        method: 'GET',
        url: Uri.parse('https://$host$encodedPath'),
      );
      expect(
        text,
        '$nonce\nGET\n$decodedPath\n$host\n',
      );
      // 末尾那个换行是最容易漏的一处。
      expect(text.endsWith('\n'), isTrue);
      expect(text.split('\n'), hasLength(5));
    });

    test('路径先解码再签名', () {
      final String text = NdAuthSigner.buildSigningString(
        nonce: nonce,
        method: 'GET',
        url: Uri.parse('https://$host$encodedPath'),
      );
      expect(text, contains(decodedPath));
      expect(text, isNot(contains('%E4%B9%89')));
    });

    test('hostname 不含端口', () {
      final String text = NdAuthSigner.buildSigningString(
        nonce: nonce,
        method: 'GET',
        url: Uri.parse('https://$host:8443$encodedPath'),
      );
      expect(text, endsWith('\n$host\n'));
      expect(text, isNot(contains('8443')));
    });

    test('query 保留在路径之后，且保持编码原样', () {
      final String text = NdAuthSigner.buildSigningString(
        nonce: nonce,
        method: 'GET',
        url: Uri.parse('https://$host/zxx/detail.json?a=1&b=2'),
      );
      expect(text, '$nonce\nGET\n/zxx/detail.json?a=1&b=2\n$host\n');
    });

    test('方法名统一大写', () {
      final String text = NdAuthSigner.buildSigningString(
        nonce: nonce,
        method: 'get',
        url: Uri.parse('https://$host/a.pdf'),
      );
      expect(text.split('\n')[1], 'GET');
    });
  });

  group('mac 计算（已知答案）', () {
    // 期望值来自独立实现（Python 的 hmac + base64），不是从本实现反推的。
    test('中文路径 + 固定 nonce（无 query）', () {
      final String header = NdAuthSigner().headerValue(
        credential: const NdCredential(accessToken: accessToken, macKey: macKey),
        method: 'GET',
        url: Uri.parse('https://$host$encodedPath'),
        nonce: nonce,
      );
      expect(
        header,
        'MAC id="$accessToken",nonce="$nonce",mac="Jv0czrA+3fXoSsDD81oMTbqxZLMnY91tV9Ml2DEAafM="',
      );
    });

    test('带 query', () {
      final String header = NdAuthSigner().headerValue(
        credential: const NdCredential(accessToken: accessToken, macKey: macKey),
        method: 'GET',
        url: Uri.parse(
          'https://$host/zxx/ndrv2/resources/details/x.json?a=1&b=2',
        ),
        nonce: nonce,
      );
      expect(
        header,
        'MAC id="$accessToken",nonce="$nonce",mac="SvvtKetwMHfvWOLlZImad7izpckro/Sybl9ZcFWGleQ="',
      );
    });

    test('方法名参与签名', () {
      final String get = NdAuthSigner.signMac(
        NdAuthSigner.buildSigningString(
          nonce: nonce,
          method: 'GET',
          url: Uri.parse('https://$host/a.pdf'),
        ),
        macKey,
      );
      final String post = NdAuthSigner.signMac(
        NdAuthSigner.buildSigningString(
          nonce: nonce,
          method: 'POST',
          url: Uri.parse('https://$host/a.pdf'),
        ),
        macKey,
      );
      expect(get, isNot(post));
    });

    test('换一个 URL 就必须重算（签名不可跨 URL 复用）', () {
      final String a = NdAuthSigner.signMac(
        NdAuthSigner.buildSigningString(
          nonce: nonce,
          method: 'GET',
          url: Uri.parse('https://$host/a.pdf'),
        ),
        macKey,
      );
      final String b = NdAuthSigner.signMac(
        NdAuthSigner.buildSigningString(
          nonce: nonce,
          method: 'GET',
          url: Uri.parse('https://$host/b.pdf'),
        ),
        macKey,
      );
      expect(a, isNot(b));
    });
  });

  group('生产路径的 nonce', () {
    test('不传 nonce 时结构正确', () {
      final String header = NdAuthSigner().headerValue(
        credential: const NdCredential(accessToken: accessToken, macKey: macKey),
        method: 'GET',
        url: Uri.parse('https://$host/a.pdf'),
      );
      expect(
        header,
        matches(RegExp(r'^MAC id="test-access-token",nonce="\d+:[0-9A-Z]{8}",mac=".+="$')),
      );
    });
  });

  group('nonce', () {
    test('时间戳部分等于注入时钟加 diff', () {
      final NdAuthSigner signer = NdAuthSigner(
        random: Random(1),
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final String value = signer.issueNonce(500);
      expect(value, startsWith('1700000000500:'));
      expect(value.split(':').last, hasLength(8));
    });

    test('后缀只取字符表里的字符', () {
      final NdAuthSigner signer = NdAuthSigner(
        random: Random(7),
        clock: () => DateTime.fromMillisecondsSinceEpoch(0),
      );
      for (int i = 0; i < 50; i++) {
        final String suffix = signer.issueNonce(0).split(':').last;
        expect(suffix, matches(RegExp(r'^[0-9A-Z]{8}$')));
      }
    });

    test('每次生成的 nonce 都不同', () {
      final NdAuthSigner signer = NdAuthSigner(clock: () => DateTime(2026));
      final Set<String> seen = <String>{
        for (int i = 0; i < 100; i++) signer.issueNonce(0),
      };
      expect(seen, hasLength(100));
    });
  });

  group('凭据缺失时的降级', () {
    test('完全没有凭据时用站点前端的匿名形式', () {
      final NdAuthSigner signer = NdAuthSigner();
      expect(
        signer.headerValue(
          credential: null,
          method: 'GET',
          url: Uri.parse('https://$host/a.pdf'),
        ),
        'MAC id="0",nonce="0",mac="0"',
      );
    });

    test('只有 access_token 没有 mac_key 时，id 换成该令牌但仍不签名', () {
      final NdAuthSigner signer = NdAuthSigner();
      expect(
        signer.headerValue(
          credential: const NdCredential(accessToken: 'only-token'),
          method: 'GET',
          url: Uri.parse('https://$host/a.pdf'),
        ),
        'MAC id="only-token",nonce="0",mac="0"',
      );
    });
  });
}
