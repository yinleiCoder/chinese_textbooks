import 'package:json_annotation/json_annotation.dart';

part 'api_response.g.dart';

/// 服务端统一响应信封：`{ "code": 0, "message": "ok", "data": ... }`。
///
/// 用泛型 + `genericArgumentFactories` 让代码生成器为 `data` 也生成解析代码，
/// 调用方直接写 `ApiResponse<List<Textbook>>` 即可，
/// 不需要手写 `data as List` 这类不安全且容易写错的强制转换。
///
/// 后端信封结构不同时，只需要改这一个类与 `ApiClient.envelope` 解码器，
/// 业务代码不受影响。
@JsonSerializable(genericArgumentFactories: true)
final class ApiResponse<T> {
  const ApiResponse({required this.code, required this.message, this.data});

  /// 从 JSON 构造。
  ///
  /// [fromJsonT] 由代码生成器注入，负责解析 `data` 字段。
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$ApiResponseFromJson(json, fromJsonT);

  /// 业务成功码。
  static const int successCode = 0;

  /// 业务返回码，[successCode] 表示成功。
  final int code;

  /// 服务端提示文案。
  final String message;

  /// 业务数据。
  final T? data;

  /// 是否成功。
  bool get isSuccess => code == successCode;

  /// 序列化为 JSON。
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) =>
      _$ApiResponseToJson(this, toJsonT);

  @override
  String toString() =>
      'ApiResponse(code: $code, message: $message, data: $data)';
}
