import 'package:dio/dio.dart';

import '../services/http/http.dart';
import '../services/logger/app_logger.dart';
import '../utils/utils.dart';
import '../values/values.dart';
import 'api_response.dart';

/// 把顶层 JSON 转换成业务结果的解码器。
///
/// 返回值是 [Result] 而不是裸数据，是为了让**业务层的失败**
/// （如信封里的 `code != 0`）和**传输层的失败**（超时、5xx）
/// 能在同一个类型里汇合，调用方只需要处理一次错误。
typedef ResultDecoder<T> = Result<T> Function(Object? data);

/// 接口客户端。
///
/// 它是业务代码接触网络的**唯一入口**，承担三件事：
/// 1. 把 `DioException` 收敛成 [AppFailure]，业务层不必再 import `dio`；
/// 2. 把返回值统一包成 [Result]，消除 try/catch；
/// 3. 记录失败日志，便于定位。
///
/// 这里刻意不提供"直接返回 `Map<String, dynamic>`"的方法。
/// 强制要求传入解码器，是为了让每个接口都有明确的返回类型，
/// 避免弱类型数据一路漂到 UI 层再崩在某个字段上。
final class ApiClient {
  ApiClient({
    required this._dio,
    required this._failureMapper,
    required this._logger,
  });

  final Dio _dio;
  final FailureMapper _failureMapper;
  final AppLogger _logger;

  /// 底层客户端，供少数需要直接控制请求过程（如上传进度）的场景使用。
  Dio get dio => _dio;

  // ==================== 快捷方法 ====================

  /// GET 请求。
  Future<Result<T>> get<T>(
    String path, {
    required ResultDecoder<T> decoder,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request<T>(
    path,
    method: 'GET',
    decoder: decoder,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// POST 请求。
  Future<Result<T>> post<T>(
    String path, {
    required ResultDecoder<T> decoder,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request<T>(
    path,
    method: 'POST',
    decoder: decoder,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// PUT 请求。
  Future<Result<T>> put<T>(
    String path, {
    required ResultDecoder<T> decoder,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request<T>(
    path,
    method: 'PUT',
    decoder: decoder,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// PATCH 请求。
  Future<Result<T>> patch<T>(
    String path, {
    required ResultDecoder<T> decoder,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request<T>(
    path,
    method: 'PATCH',
    decoder: decoder,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// DELETE 请求。
  Future<Result<T>> delete<T>(
    String path, {
    required ResultDecoder<T> decoder,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request<T>(
    path,
    method: 'DELETE',
    decoder: decoder,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  // ==================== 通用请求 ====================

  /// 发起请求并把结果收敛为 [Result]。
  Future<Result<T>> request<T>(
    String path, {
    required String method,
    required ResultDecoder<T> decoder,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final Response<dynamic> response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
        cancelToken: cancelToken,
      );
      return decoder(response.data);
    } on DioException catch (error, stackTrace) {
      final AppFailure failure = _failureMapper.map(error);
      _logger.w(
        '接口失败：$method $path → ${failure.runtimeType}',
        error,
        stackTrace,
      );
      return Failure<T>(failure);
    } on Object catch (error, stackTrace) {
      // 解码器之外抛出的异常（理论上不该发生），兜底成解析失败，
      // 保证 ApiClient 的返回值永远是 Result，不会有异常穿透到状态层。
      _logger.e('接口未预期异常：$method $path', error, stackTrace);
      return Failure<T>(
        ParseFailure(
          message: AppStrings.errorParse,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ==================== 预置解码器 ====================

  /// 直接把顶层 JSON 交给 [fromData] 解析。
  ///
  /// 适用于后端直接返回数据、没有 `{code, message, data}` 信封的接口。
  static ResultDecoder<T> raw<T>(T Function(Object? data) fromData) {
    return (Object? data) {
      try {
        return Success<T>(fromData(data));
      } on Object catch (error, stackTrace) {
        return Failure<T>(
          ParseFailure(
            message: AppStrings.errorParse,
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      }
    };
  }

  /// 先解开 [ApiResponse] 信封，成功后再交给 [fromData] 解析 `data`。
  ///
  /// ```dart
  /// api.get(
  ///   '/textbooks',
  ///   decoder: ApiClient.envelope<List<Textbook>>(
  ///     (Object? data) => (data! as List<dynamic>)
  ///         .map((e) => Textbook.fromJson(e as Map<String, dynamic>))
  ///         .toList(),
  ///   ),
  /// );
  /// ```
  static ResultDecoder<T> envelope<T>(T Function(Object? data) fromData) {
    return (Object? data) {
      try {
        if (data is! Map<String, dynamic>) {
          return Failure<T>(
            ParseFailure(
              message: AppStrings.errorParse,
              cause: '期望响应为 JSON 对象，实际为 ${data.runtimeType}',
            ),
          );
        }
        final ApiResponse<Object?> response = ApiResponse<Object?>.fromJson(
          data,
          (Object? json) => json,
        );
        if (!response.isSuccess) {
          return Failure<T>(
            BusinessFailure(
              code: '${response.code}',
              message: response.message,
              data: response.data,
            ),
          );
        }
        return Success<T>(fromData(response.data));
      } on Object catch (error, stackTrace) {
        return Failure<T>(
          ParseFailure(
            message: AppStrings.errorParse,
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      }
    };
  }

  /// 不关心响应体，只关心请求是否成功。
  static ResultDecoder<void> get ignoreBody =>
      (Object? _) => const Success<void>(null);
}
