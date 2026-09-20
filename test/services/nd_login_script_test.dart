import 'dart:convert';

import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/services/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// 凭据提取的解析逻辑。
///
/// 这一段没有 UI、没有网络，但**错了就整个下载功能不可用**，
/// 而线上表现只是一个笼统的 401，很难反推。所以每种形态都要钉住。
void main() {
  const String credentials =
      '{"access_token":"tok-123","mac_key":"mac-456","diff":-1200}';

  group('localStorage 值的两种形态', () {
    test('直接就是凭据对象', () {
      final NdCredential? credential = NdCredential.tryParseLocalStorageValue(
        credentials,
      );
      expect(credential?.accessToken, 'tok-123');
      expect(credential?.macKey, 'mac-456');
      expect(credential?.diff, -1200);
      expect(credential?.canSign, isTrue);
    });

    test('凭据被包在 value 字段里，且那一层还是字符串', () {
      // 参考项目 issue #89：同前缀的 sdk_cache 是账号资料缓存，
      // 只有 token 结尾的那个才是凭据，而它的值还多包了一层。
      final String wrapped = jsonEncode(<String, String>{
        'value': credentials,
        'expire': '1700000000000',
      });
      final NdCredential? credential = NdCredential.tryParseLocalStorageValue(
        wrapped,
      );
      expect(credential?.accessToken, 'tok-123');
      expect(credential?.canSign, isTrue);
    });

    test('只有 access_token 时能解析，但标记为不可签名', () {
      final NdCredential? credential = NdCredential.tryParseLocalStorageValue(
        '{"access_token":"only-token"}',
      );
      expect(credential, isNotNull);
      expect(
        credential?.canSign,
        isFalse,
        reason: '没有 mac_key 就签不出名，不能当作登录成功',
      );
    });

    test('账号资料缓存（没有 access_token）解析为 null', () {
      expect(
        NdCredential.tryParseLocalStorageValue('{"avatar":"x","nickname":"y"}'),
        isNull,
      );
    });

    test('非 JSON 输入返回 null 而不是抛异常', () {
      expect(NdCredential.tryParseLocalStorageValue('随便一段文字'), isNull);
      expect(NdCredential.tryParseLocalStorageValue(''), isNull);
    });
  });

  group('探针结果解析', () {
    test('页面返回找到凭据', () {
      final CredentialProbe probe = NdLoginScript.parseProbe(
        jsonEncode(<String, Object?>{
          'found': true,
          'key': 'ND_UC_AUTH-a&b&token',
          'value': credentials,
        }),
      );
      expect(probe.isFound, isTrue);
      expect(probe.isUsable, isTrue);
      expect(probe.credential?.accessToken, 'tok-123');
    });

    test('页面返回未找到——这不是错误，应当继续轮询', () {
      final CredentialProbe probe = NdLoginScript.parseProbe(
        jsonEncode(<String, Object?>{'found': false}),
      );
      expect(probe.isFound, isFalse);
      expect(probe.error, isNull);
      expect(probe.isUsable, isFalse);
    });

    test('页面里抛异常', () {
      final CredentialProbe probe = NdLoginScript.parseProbe(
        jsonEncode(<String, Object?>{'found': false, 'error': 'SecurityError'}),
      );
      expect(probe.error, 'SecurityError');
    });

    test('平台已经把对象解码好时同样能处理', () {
      final CredentialProbe probe = NdLoginScript.parseProbe(
        <String, Object?>{
          'found': true,
          'value': credentials,
        },
      );
      expect(probe.isUsable, isTrue);
    });

    test('空返回值、null、非 JSON 都按"未找到"处理', () {
      for (final Object? raw in <Object?>[null, '', 'null', '不是 JSON']) {
        expect(
          NdLoginScript.parseProbe(raw).isUsable,
          isFalse,
          reason: 'raw=$raw',
        );
      }
    });
  });

  group('凭据键名匹配', () {
    test('只认 token 结尾的那一项', () {
      final RegExp pattern = NdLoginScript.credentialKeyPattern;
      expect(pattern.hasMatch('ND_UC_AUTH-abc&def&token'), isTrue);
      // 同前缀的账号资料缓存——读到它只会白忙一场。
      expect(pattern.hasMatch('ND_UC_AUTH-abc&def&sdk_cache'), isFalse);
      expect(pattern.hasMatch('OTHER_KEY'), isFalse);
    });
  });

  group('凭据对象的调试输出', () {
    test('toString 不泄漏任何凭据内容', () {
      const NdCredential credential = NdCredential(
        accessToken: 'super-secret-token',
        macKey: 'super-secret-key',
      );
      final String text = credential.toString();
      expect(text, isNot(contains('super-secret-token')));
      expect(text, isNot(contains('super-secret-key')));
    });
  });
}
