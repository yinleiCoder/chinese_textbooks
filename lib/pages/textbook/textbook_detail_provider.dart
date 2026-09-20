import 'package:flutter/foundation.dart';

import '../../apis/apis.dart';
import '../../entity/entity.dart';
import '../../utils/utils.dart';

/// 详情页的加载状态。
enum DetailStatus { loading, ready, failed }

/// 教材详情页的页面私有状态。
///
/// 只有一个异步请求，没有跨组件共享的需求，本可以用 `FutureBuilder` 打发。
/// 仍然单独成类，是为了后续要加的"下载 / 阅读"动作有个自然的落脚点——
/// 那时它就需要在多个组件之间共享了。
final class TextbookDetailProvider extends ChangeNotifier {
  TextbookDetailProvider({
    required this._api,
    required this.contentId,
    this.summary,
  });

  final TextbookApi _api;

  /// 教材 id。
  final String contentId;

  /// 清单里的那一条。
  ///
  /// 分类路径、出版社这些信息只有清单里有，详情接口不返回，
  /// 因此从目录页跳过来时一并带上。深链进来时为 `null`，界面少显示几行即可。
  final Textbook? summary;

  DetailStatus _status = DetailStatus.loading;
  TextbookDetail? _detail;
  AppFailure? _failure;

  DetailStatus get status => _status;
  TextbookDetail? get detail => _detail;
  AppFailure? get failure => _failure;

  /// 是否拿到了可下载的源文件。
  bool get isDownloadable => _detail?.isDownloadable ?? false;

  /// 标题：优先用详情返回的，退回清单里的。
  String get title => _detail?.title ?? summary?.title ?? '';

  /// 拉取详情。
  Future<void> load() async {
    _status = DetailStatus.loading;
    _failure = null;
    notifyListeners();

    final Result<TextbookDetail> result = await _api.fetchDetail(contentId);
    switch (result) {
      case Success<TextbookDetail>(:final TextbookDetail data):
        _detail = data;
        _status = DetailStatus.ready;
      case Failure<TextbookDetail>(:final AppFailure failure):
        _failure = failure;
        _status = DetailStatus.failed;
    }
    notifyListeners();
  }
}
