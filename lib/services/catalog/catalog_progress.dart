import 'package:equatable/equatable.dart';

/// 目录加载所处的阶段。
enum CatalogStage {
  /// 尚未开始。
  idle,

  /// 正在探测版本（一个 1KB 的请求）。
  checking,

  /// 正在下载分片。
  downloading,

  /// 正在解析分片。
  parsing,

  /// 正在建索引。
  indexing,

  /// 已就绪。
  ready,

  /// 失败。
  failed,
}

/// 目录加载进度。
///
/// 进度按**阶段加权**上报：下载占 0~70%、解析占 70~95%、建索引占 95~100%。
/// 不这样做的话，进度条会在下载完成后长时间停在同一个数字上——
/// 解析 40MB JSON 对大文件来说并不快，用户会以为卡死了。
final class CatalogProgress extends Equatable {
  const CatalogProgress({
    required this.stage,
    this.completedParts = 0,
    this.totalParts = 0,
    this.receivedBytes = 0,
    this.totalBytes,
    this.message,
  });

  /// 尚未开始。
  static const CatalogProgress idle = CatalogProgress(stage: CatalogStage.idle);

  /// 已就绪。
  static const CatalogProgress ready = CatalogProgress(
    stage: CatalogStage.ready,
  );

  /// 当前阶段。
  final CatalogStage stage;

  /// 已完成的分片数。
  final int completedParts;

  /// 分片总数。
  final int totalParts;

  /// 当前分片已接收的字节数。
  final int receivedBytes;

  /// 当前分片的总字节数，平台未给出时为 `null`。
  final int? totalBytes;

  /// 附加说明，用于界面展示更具体的信息。
  final String? message;

  /// 总体进度，0~1。
  ///
  /// 返回 `null` 表示进度不确定，界面应显示不确定态的进度指示器，
  /// 而不是画一个停在 0% 的条。
  double? get fraction {
    switch (stage) {
      case CatalogStage.idle:
      case CatalogStage.checking:
      case CatalogStage.failed:
        return null;
      case CatalogStage.ready:
        return 1;
      case CatalogStage.indexing:
        return 0.95;
      case CatalogStage.downloading:
      case CatalogStage.parsing:
        if (totalParts == 0) {
          return null;
        }
        final double within = (totalBytes ?? 0) > 0
            ? receivedBytes / totalBytes!
            : 0;
        final double done = (completedParts + within.clamp(0, 1)) / totalParts;
        return stage == CatalogStage.downloading
            ? done * 0.7
            : 0.7 + done * 0.25;
    }
  }

  /// 派生新进度。
  CatalogProgress copyWith({
    CatalogStage? stage,
    int? completedParts,
    int? totalParts,
    int? receivedBytes,
    int? totalBytes,
    String? message,
  }) => CatalogProgress(
    stage: stage ?? this.stage,
    completedParts: completedParts ?? this.completedParts,
    totalParts: totalParts ?? this.totalParts,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    message: message ?? this.message,
  );

  @override
  List<Object?> get props => <Object?>[
    stage,
    completedParts,
    totalParts,
    receivedBytes,
    totalBytes,
    message,
  ];

  @override
  String toString() =>
      'CatalogProgress(${stage.name}, $completedParts/$totalParts)';
}

/// 进度回调。
typedef CatalogProgressCallback = void Function(CatalogProgress progress);
