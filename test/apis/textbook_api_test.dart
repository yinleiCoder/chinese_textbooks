import 'dart:convert';
import 'dart:typed_data';

import 'package:chinese_textbooks/apis/apis.dart';
import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/services/http/http.dart';
import 'package:chinese_textbooks/services/logger/app_logger.dart';
import 'package:chinese_textbooks/utils/utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回固定 JSON（或状态码）的假适配器。
final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.body, this.statusCode = 200});

  final Object? body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (body == null) {
      return ResponseBody.fromString('', statusCode);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TextbookApi buildApi(Object? body, {int statusCode = 200}) {
    final AppLogger logger = AppLogger(verbose: false);
    return TextbookApi(
      apiClient: ApiClient(
        dio: Dio()..httpClientAdapter = _StubAdapter(body: body, statusCode: statusCode),
        failureMapper: const DefaultFailureMapper(),
        logger: logger,
      ),
      logger: logger,
    );
  }

  /// 构造一个仿真详情的 `ti_items`。
  List<Map<String, dynamic>> items({bool withSource = true, bool markSourceFlag = true}) {
    return <Map<String, dynamic>>[
      if (withSource)
        <String, dynamic>{
          'ti_file_flag': 'source',
          'ti_format': 'pdf',
          if (markSourceFlag) 'ti_is_source_file': true,
          'ti_size': 22620491,
          'ti_storages': <String>[
            'https://r1-ndr-private.ykt.cbern.com.cn/a/b.pkg/义务教育教科书•语文.pdf',
            'https://r2-ndr-private.ykt.cbern.com.cn/a/b.pkg/义务教育教科书•语文.pdf',
            'https://r3-ndr-private.ykt.cbern.com.cn/a/b.pkg/义务教育教科书•语文.pdf',
          ],
          'custom_properties': <String, dynamic>{
            'requirements': <Map<String, String>>[
              <String, String>{'name': 'pagesize', 'value': '128'},
              <String, String>{'name': 'width', 'value': '696'},
            ],
          },
        },
      // 逐页图片：必须被跳过。
      <String, dynamic>{
        'ti_file_flag': 'image',
        'ti_format': 'folder',
        'ti_storages': <String>['https://r1-ndr-private.ykt.cbern.com.cn/a/b.t/x/transcode/image'],
      },
    ];
  }

  group('源文件提取', () {
    test('认 ti_is_source_file，并保留全部三个镜像', () async {
      final Result<TextbookDetail> result = await buildApi(<String, dynamic>{
        'global_title': <String, String>{'zh-CN': '义务教育教科书·语文一年级上册'},
        'ti_items': items(),
      }).fetchDetail('abc');

      final TextbookDetail detail = result.dataOrNull!;
      expect(detail.title, '义务教育教科书·语文一年级上册');
      expect(detail.pdfMirrors, hasLength(3));
      expect(detail.pdfMirrors.first.host, 'r1-ndr-private.ykt.cbern.com.cn');
      expect(detail.pdfMirrors.last.host, 'r3-ndr-private.ykt.cbern.com.cn');
      expect(detail.sizeBytes, 22620491);
      expect(detail.pageCount, 128, reason: '页数要取 requirements 里的 pagesize');
      expect(detail.readableSize, '21.6 MB');
    });

    test('非 ASCII 路径被正确百分号编码', () async {
      final Result<TextbookDetail> result = await buildApi(<String, dynamic>{
        'ti_items': items(),
      }).fetchDetail('abc');

      final Uri url = result.dataOrNull!.pdfMirrors.first;
      expect(url.toString(), contains('%E4%B9%89'));   // 「义」
      // 签名要用解码后的路径，两者必须都能取到。
      expect(Uri.decodeComponent(url.path), contains('义务教育教科书'));
    });

    test('漏标 ti_is_source_file 时按 ti_file_flag 兜底', () async {
      final Result<TextbookDetail> result = await buildApi(<String, dynamic>{
        'ti_items': items(markSourceFlag: false),
      }).fetchDetail('abc');

      expect(result.dataOrNull?.pdfMirrors, hasLength(3));
    });

    test('ti_storages 为空时退回 ti_storage 模板', () async {
      final Result<TextbookDetail> result = await buildApi(<String, dynamic>{
        'ti_items': <Map<String, dynamic>>[
          <String, dynamic>{
            'ti_file_flag': 'source',
            'ti_format': 'pdf',
            'ti_is_source_file': true,
            'ti_storage': r'cs_path:${ref-path}/edu_product/esp/assets/a.pkg/b.pdf',
          },
        ],
      }).fetchDetail('abc');

      expect(
        result.dataOrNull!.pdfMirrors.single.toString(),
        'https://r1-ndr-private.ykt.cbern.com.cn/edu_product/esp/assets/a.pkg/b.pdf',
      );
    });

    test('没有任何源文件时归为"暂不提供在线阅读"', () async {
      final Result<TextbookDetail> result = await buildApi(<String, dynamic>{
        'ti_items': items(withSource: false),
      }).fetchDetail('abc');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<BusinessFailure>());
      expect(
        (result.failureOrNull! as BusinessFailure).code,
        TextbookApi.detailUnavailableCode,
      );
    });
  });

  group('失败归类', () {
    // 这一条是关键：详情接口在公开主机上，403 与登录态无关。
    // 不改写的话，界面会显示"没有访问权限"，用户会以为是账号问题。
    test('403 改写成业务失败，而不是认证失败', () async {
      final Result<TextbookDetail> result = await buildApi(
        null,
        statusCode: 403,
      ).fetchDetail('abc');

      expect(result.failureOrNull, isA<BusinessFailure>());
      expect(result.failureOrNull, isNot(isA<AuthFailure>()));
      expect(
        (result.failureOrNull! as BusinessFailure).code,
        TextbookApi.detailUnavailableCode,
      );
    });

    test('5xx 仍然是服务端失败', () async {
      final Result<TextbookDetail> result = await buildApi(
        null,
        statusCode: 500,
      ).fetchDetail('abc');

      expect(result.failureOrNull, isA<ServerFailure>());
    });
  });
}
