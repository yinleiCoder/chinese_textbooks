import 'dart:io';
import 'dart:typed_data';

import 'package:chinese_textbooks/apis/apis.dart';
import 'package:chinese_textbooks/services/http/http.dart';
import 'package:chinese_textbooks/services/logger/app_logger.dart';
import 'package:chinese_textbooks/utils/utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个只回固定状态码的假适配器。
///
/// 用它而不是起一个本地 server：这里要验的是"拿到 304 之后代码怎么处理文件"，
/// 与网络无关，越少的活动部件越好。
final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusCode);

  final int statusCode;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody(
      const Stream<Uint8List>.empty(),
      statusCode,
      headers: <String, List<String>>{
        HttpHeaders.etagHeader: <String>['"etag-value"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory sandbox;
  late File target;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nd_catalog_api');
    target = File('${sandbox.path}/tags.json');
  });

  tearDown(() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  CatalogApi buildApi(HttpClientAdapter adapter) {
    final AppLogger logger = AppLogger(verbose: false);
    final Dio dio = Dio()..httpClientAdapter = adapter;
    return CatalogApi(
      apiClient: ApiClient(
        dio: dio,
        failureMapper: const DefaultFailureMapper(),
        logger: logger,
      ),
      failureMapper: const DefaultFailureMapper(),
      logger: logger,
    );
  }

  group('304 与本地文件', () {
    // 这一条是回归测试：早先的实现在收到 304 时无条件删除目标文件，
    // 而标签树的目标就是正式的 tags.json（不是暂存文件），
    // 导致每次增量探测都把本地标签树抹掉，用户下次启动就变成"没有目录数据"。
    test('不能删掉已经存在的目标文件', () async {
      const String existing = '{"hierarchies":[]}';
      await target.writeAsString(existing);

      final _FakeAdapter adapter = _FakeAdapter(HttpStatus.notModified);
      final result = await buildApi(adapter).downloadTagTree(
        target,
        etag: '"etag-value"',
      );

      expect(adapter.calls, 1);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.changed, isFalse);
      expect(
        target.existsSync(),
        isTrue,
        reason: '304 表示本地内容仍然有效，不能把它删掉',
      );
      expect(await target.readAsString(), existing);
    });

    test('目标文件原本不存在时，304 之后也不该留下空文件', () async {
      final result = await buildApi(
        _FakeAdapter(HttpStatus.notModified),
      ).downloadTagTree(target);

      expect(result.dataOrNull?.changed, isFalse);
      expect(
        target.existsSync(),
        isFalse,
        reason: '304 没有响应体，不该留下一个空文件冒充数据',
      );
    });
  });

  group('200 正常下载', () {
    test('写入文件并带回 ETag', () async {
      final _FakeAdapter adapter = _FakeAdapter(HttpStatus.ok);
      final result = await buildApi(adapter).downloadTagTree(target);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.changed, isTrue);
      expect(result.dataOrNull?.etag, '"etag-value"');
      expect(target.existsSync(), isTrue);
    });
  });

  group('失败路径', () {
    test('5xx 归类为服务端失败', () async {
      final result = await buildApi(
        _FakeAdapter(HttpStatus.internalServerError),
      ).downloadTagTree(target);

      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull,
        isA<ServerFailure>(),
        reason: '5xx 应当是 ServerFailure 而不是笼统的未知错误',
      );
    });

    test('403 归类为认证失败', () async {
      final result = await buildApi(
        _FakeAdapter(HttpStatus.forbidden),
      ).downloadTagTree(target);

      expect(result.failureOrNull, isA<AuthFailure>());
    });
  });
}
