import 'package:meta/meta.dart';

import 'failure.dart';

/// 显式的结果类型，替代"抛异常 + try/catch"的隐式错误传递。
///
/// 为什么不用异常：
/// - 异常会污染函数签名，调用方无从得知哪些调用可能失败；
/// - `try/catch` 容易漏接，且很难在编译期发现；
/// - [Result] 把"成功"和"失败"都变成**返回值**，配合 Dart 3 的
///   `switch` 模式匹配，未处理的分支会在编译期报错。
///
/// 典型用法：
/// ```dart
/// final Result<List<Textbook>> result = await api.fetchTextbooks();
/// switch (result) {
///   case Success(:final data):
///     render(data);
///   case Failure(:final failure):
///     showError(failure.message);
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// 构造成功结果。
  const factory Result.success(T data) = Success<T>;

  /// 构造失败结果。
  const factory Result.failure(AppFailure failure) = Failure<T>;

  /// 是否成功。
  bool get isSuccess => this is Success<T>;

  /// 是否失败。
  bool get isFailure => this is Failure<T>;

  /// 成功时返回数据，失败时返回 `null`。
  T? get dataOrNull => switch (this) {
    Success<T>(:final T data) => data,
    Failure<T>() => null,
  };

  /// 失败时返回错误，成功时返回 `null`。
  AppFailure? get failureOrNull => switch (this) {
    Success<T>() => null,
    Failure<T>(:final AppFailure failure) => failure,
  };

  /// 折叠两个分支，把 [Result] 归约为一个普通值。
  ///
  /// 这是唯一"逃出" [Result] 的方式，UI 层通常只需要它。
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) => switch (this) {
    Success<T>(:final T data) => onSuccess(data),
    Failure<T>(:final AppFailure failure) => onFailure(failure),
  };

  /// 保持成功/失败状态不变，只转换成功值。
  Result<R> map<R>(R Function(T data) transform) => switch (this) {
    Success<T>(:final T data) => Success<R>(transform(data)),
    Failure<T>(:final AppFailure failure) => Failure<R>(failure),
  };

  /// 在成功分支上串联另一个可能失败的异步操作。
  ///
  /// 与 [map] 的区别是 [transform] 自身返回 [Result]，
  /// 因此不会出现 `Result<Result<R>>` 的嵌套。
  Result<R> flatMap<R>(Result<R> Function(T data) transform) => switch (this) {
    Success<T>(:final T data) => transform(data),
    Failure<T>(:final AppFailure failure) => Failure<R>(failure),
  };

  /// 成功时返回数据，失败时由 [orElse] 兜底。
  T getOrElse(T Function(AppFailure failure) orElse) => switch (this) {
    Success<T>(:final T data) => data,
    Failure<T>(:final AppFailure failure) => orElse(failure),
  };

  /// 成功时返回数据，失败时抛出 [AppFailure]。
  ///
  /// 仅在"确知不会失败"或"框架强制要求抛异常"的场景下使用。
  T getOrThrow() => switch (this) {
    Success<T>(:final T data) => data,
    Failure<T>(:final AppFailure failure) => throw failure,
  };

  /// 把失败结果替换为另一个值，使结果重新变为成功。
  Result<T> recover(T Function(AppFailure failure) transform) => switch (this) {
    Success<T>() => this,
    Failure<T>(:final AppFailure failure) => Success<T>(transform(failure)),
  };

  /// 在失败分支上做副作用（打点、上报），不影响结果本身。
  ///
  /// 刻意不返回 `this`：返回值会诱导写出 `result.onFailure(log).map(...)`
  /// 这类"读起来像纯函数、实际夹带副作用"的链式调用。
  void onFailure(void Function(AppFailure failure) action) {
    if (this case Failure<T>(:final AppFailure failure)) {
      action(failure);
    }
  }

  /// 把可能抛异常的异步操作包装成 [Result]。
  ///
  /// 用于收拢第三方库（平台通道、文件读写）抛出的异常，
  /// 避免异常穿透到状态层。
  static Future<Result<T>> guard<T>(
    Future<T> Function() action, {
    required AppFailure Function(Object error, StackTrace stackTrace) onError,
  }) async {
    try {
      return Success<T>(await action());
    } on Object catch (error, stackTrace) {
      return Failure<T>(onError(error, stackTrace));
    }
  }

  /// 把可能抛异常的同步操作包装成 [Result]。
  static Result<T> guardSync<T>(
    T Function() action, {
    required AppFailure Function(Object error, StackTrace stackTrace) onError,
  }) {
    try {
      return Success<T>(action());
    } on Object catch (error, stackTrace) {
      return Failure<T>(onError(error, stackTrace));
    }
  }
}

/// 成功结果。
@immutable
final class Success<T> extends Result<T> {
  const Success(this.data);

  /// 业务数据。
  final T data;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Success<T> && other.data == data);

  @override
  int get hashCode => Object.hash(Success<T>, data);

  @override
  String toString() => 'Success<$T>($data)';
}

/// 失败结果。
@immutable
final class Failure<T> extends Result<T> {
  const Failure(this.failure);

  /// 失败详情。
  final AppFailure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Failure<T> && other.failure == failure);

  @override
  int get hashCode => Object.hash(Failure<T>, failure);

  @override
  String toString() => 'Failure<$T>($failure)';
}

/// 面向 `Future<Result<T>>` 的链式辅助。
extension FutureResultX<T> on Future<Result<T>> {
  /// 在成功分支上串联另一个异步操作，等价于 `await` 后再 [Result.flatMap]。
  Future<Result<R>> thenFlatMap<R>(
    Future<Result<R>> Function(T data) transform,
  ) async {
    final Result<T> current = await this;
    return switch (current) {
      Success<T>(:final T data) => transform(data),
      Failure<T>(:final AppFailure failure) => Failure<R>(failure),
    };
  }

  /// 转换成功值，保持失败状态。
  Future<Result<R>> mapResult<R>(R Function(T data) transform) async {
    final Result<T> current = await this;
    return current.map(transform);
  }
}
