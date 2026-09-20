import 'dart:convert';

import 'package:equatable/equatable.dart';

/// 平台登录凭据。
///
/// 三个字段都来自用户**本人登录后**平台写入浏览器 localStorage 的那段 JSON，
/// 本应用不做任何推导或伪造。
///
/// 存储要求：必须进 `flutter_secure_storage`（Android Keystore / Windows DPAPI）。
/// [macKey] 是签名密钥，落明文等同于把账号交出去——桌面端安全存储不可用时
/// 宁可只保留在内存里，也不能降级写进 `shared_preferences`。
final class NdCredential extends Equatable {
  const NdCredential({required this.accessToken, this.macKey, this.diff = 0});

  /// 从 localStorage 里的那段 JSON 解析。
  ///
  /// 期望形如 `{"access_token":"...","mac_key":"...","diff":123}`。
  /// 解析失败返回 `null` 而不是抛异常——这段文本来自用户粘贴，
  /// 是典型的不可信输入，调用方需要能优雅地提示"格式不对"。
  static NdCredential? tryParse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return fromJsonMap(decoded);
  }

  /// 解析平台写进 localStorage 的那个值。
  ///
  /// 实测存在两种形态，都要认：
  /// 1. 直接就是 `{"access_token":...,"mac_key":...,"diff":...}`；
  /// 2. 外面还包了一层，凭据在 `value` 字段里，且**那一层还是字符串**
  ///    （要再解析一次）。参考项目的 issue #89 就是漏了这层包装，
  ///    结果读到的是账号资料缓存而不是凭据。
  static NdCredential? tryParseLocalStorageValue(String raw) {
    final NdCredential? direct = tryParse(raw);
    if (direct != null) {
      return direct;
    }

    final Object? outer;
    try {
      outer = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (outer is! Map<String, dynamic>) {
      return null;
    }
    final Object? value = outer['value'];
    return value is String ? tryParse(value) : null;
  }

  /// 从已解析的 JSON 对象构造。
  static NdCredential? fromJsonMap(Map<String, dynamic> json) {
    final Object? token = json['access_token'];
    if (token is! String || token.trim().isEmpty) {
      return null;
    }
    final Object? macKey = json['mac_key'];
    final Object? diff = json['diff'];
    return NdCredential(
      accessToken: token.trim(),
      macKey: macKey is String && macKey.trim().isNotEmpty
          ? macKey.trim()
          : null,
      // diff 允许缺失：它只是本地时钟与服务器的毫秒差，缺省按 0 处理。
      diff: diff is int ? diff : 0,
    );
  }

  /// 访问令牌，同时作为签名头里的 `id`。
  final String accessToken;

  /// 签名密钥。为空时只能生成占位签名头，私有资源会 401/400。
  final String? macKey;

  /// 本地时钟相对平台服务器的毫秒差，加进 nonce 的时间戳部分。
  final int diff;

  /// 是否具备生成**真实签名**的能力。
  ///
  /// 只有 `access_token` 而没有 `mac_key` 的老格式凭据不够用，
  /// 界面应当据此提示用户重新登录。
  bool get canSign => macKey != null && macKey!.isNotEmpty;

  /// 序列化为可持久化的 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'access_token': accessToken,
    if (macKey != null) 'mac_key': macKey,
    'diff': diff,
  };

  /// 序列化为字符串，供安全存储写入。
  String encode() => jsonEncode(toJson());

  @override
  List<Object?> get props => <Object?>[accessToken, macKey, diff];

  /// **不输出任何凭据内容。**
  ///
  /// 日志、异常堆栈、调试面板里都可能打印对象，重写 `toString` 是防止
  /// 令牌泄漏的最后一道闸门。
  @override
  String toString() =>
      'NdCredential(accessToken: <已隐藏>, macKey: ${canSign ? '<已隐藏>' : 'null'})';
}
