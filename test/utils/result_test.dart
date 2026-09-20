import 'package:chinese_textbooks/utils/utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Result] 的行为约定。
///
/// 这些用例同时充当文档：读一遍就知道成功/失败两条分支各方法怎么走。
void main() {
  const AppFailure failure = NetworkFailure(message: '断网了');

  group('Result 构造与判定', () {
    test('成功结果的判定与取值', () {
      const Result<int> result = Success<int>(42);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.dataOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('失败结果的判定与取值', () {
      const Result<int> result = Failure<int>(failure);

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.failureOrNull, same(failure));
    });
  });

  group('Result.map', () {
    test('成功时转换值，失败状态保持不变', () {
      expect(const Success<int>(2).map((int v) => v * 3), const Success<int>(6));
      expect(
        const Failure<int>(failure).map((int v) => v * 3),
        const Failure<int>(failure),
      );
    });
  });

  group('Result.flatMap', () {
    test('串联成功分支，不产生 Result 嵌套', () {
      final Result<String> result = const Success<int>(2).flatMap(
        (int v) => Success<String>('值：$v'),
      );

      expect(result, const Success<String>('值：2'));
    });

    test('前一步失败时短路，后续转换不执行', () {
      bool called = false;
      final Result<String> result = const Failure<int>(failure).flatMap((
        int v,
      ) {
        called = true;
        return Success<String>('$v');
      });

      expect(called, isFalse, reason: '失败分支不应触发后续转换');
      expect(result, const Failure<String>(failure));
    });
  });

  group('Result.fold', () {
    test('把两个分支归约为同一个类型', () {
      String describe(Result<int> result) => result.fold(
        onSuccess: (int data) => '成功：$data',
        onFailure: (AppFailure error) => '失败：${error.message}',
      );

      expect(describe(const Success<int>(1)), '成功：1');
      expect(describe(const Failure<int>(failure)), '失败：断网了');
    });
  });

  group('Result.recover / getOrElse', () {
    test('recover 把失败转成成功', () {
      expect(
        const Failure<int>(failure).recover((AppFailure _) => 0),
        const Success<int>(0),
      );
    });

    test('getOrElse 在失败时给出兜底值', () {
      expect(const Failure<int>(failure).getOrElse((AppFailure _) => -1), -1);
      expect(const Success<int>(7).getOrElse((AppFailure _) => -1), 7);
    });
  });

  group('Result.guard', () {
    test('正常返回时包装为 Success', () async {
      final Result<int> result = await Result.guard<int>(
        () async => 1 + 1,
        onError: (Object error, StackTrace _) =>
            UnknownFailure(message: '$error'),
      );

      expect(result, const Success<int>(2));
    });

    test('抛出异常时收敛为 Failure，而不是让异常穿透', () async {
      final Result<int> result = await Result.guard<int>(
        () async => throw StateError('炸了'),
        onError: (Object error, StackTrace _) =>
            UnknownFailure(message: '兜底：$error'),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.message, contains('炸了'));
    });
  });
}
