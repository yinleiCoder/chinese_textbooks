import 'package:equatable/equatable.dart';

/// 下载任务的状态。
enum DownloadStatus {
  /// 已入队，等待调度。
  queued,

  /// 正在下载。
  running,

  /// 已完成并落盘。
  completed,

  /// 失败，具体原因见 [DownloadTask.failureReason]。
  failed,

  /// 用户主动取消。
  cancelled;

  /// 是否已终结（不会再变化）。
  bool get isTerminal =>
      this == DownloadStatus.completed ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.cancelled;
}

/// 失败原因。
///
/// 分类的意义在于**驱动界面给出正确的下一步动作**：
/// [authRequired] 要给登录入口，[rateLimited] 与 [network] 给重试，
/// [notFound] 与 [integrity] 则不该给重试按钮（重试多少次都一样）。
enum DownloadFailureReason {
  /// 网络异常（连接失败、超时）。
  network,

  /// 所有镜像都试过了仍然失败。
  mirrorExhausted,

  /// 401 / 403：需要登录，或凭据已失效。
  authRequired,

  /// 404：资源不存在。
  notFound,

  /// 落盘字节数与平台给出的 `ti_size` 不符。
  integrity,

  /// 本地磁盘写入失败。
  disk,

  /// 400：被限流。同址退避重试若干次后仍失败。
  rateLimited,

  /// 用户取消。
  cancelled,

  /// 无法归类。
  unknown;

  /// 是否值得让用户重试。
  bool get isRetryable => switch (this) {
    DownloadFailureReason.network => true,
    DownloadFailureReason.rateLimited => true,
    DownloadFailureReason.mirrorExhausted => true,
    DownloadFailureReason.unknown => true,
    DownloadFailureReason.authRequired => false,
    DownloadFailureReason.notFound => false,
    DownloadFailureReason.integrity => false,
    DownloadFailureReason.disk => false,
    DownloadFailureReason.cancelled => false,
  };
}

/// 一个教材下载任务。
///
/// 不可变值对象，每次状态推进产出新实例——这样 `DownloadProvider` 只要比较
/// 引用就能判断是否变化，也让事件流里的历史状态不会被后续变更污染。
///
/// 状态推进不用通用的 `copyWith`，而是给每个转移一个语义化方法
/// （[started] / [progressed] / [succeeded] / [failed] / [cancelled]）：
/// `copyWith` 在"把可空字段置空"这件事上语义含糊，
/// 而这些转移本身是有限且有明确含义的。
final class DownloadTask extends Equatable {
  const DownloadTask({
    required this.textbookId,
    required this.title,
    required this.mirrors,
    required this.expectedBytes,
    this.pageCount,
    this.status = DownloadStatus.queued,
    this.receivedBytes = 0,
    this.bytesPerSecond = 0,
    this.attempt = 0,
    this.failureReason,
    this.message,
    this.requiresAuth = false,
    this.savePath,
  });

  /// 教材 id，同时用作文件主名与任务标识。
  ///
  /// 用 id 而不是中文书名做文件名，是为了绕开 Android SAF 与 Windows
  /// 网络驱动器的编码坑，也让改书名时不必重命名文件。
  final String textbookId;

  /// 书名，仅用于界面展示。
  final String title;

  /// 候选下载地址，按平台给出的 r1 / r2 / r3 顺序。
  ///
  /// 这些是**私有域**地址。公开镜像由 `MirrorPlanner` 按需派生，不在这里存。
  final List<Uri> mirrors;

  /// 平台给出的文件字节数（`ti_size`）。
  ///
  /// 为 0 表示平台未给出大小，此时进度只能显示为不确定态。
  final int expectedBytes;

  /// 总页数，仅用于展示。
  final int? pageCount;

  /// 当前状态。
  final DownloadStatus status;

  /// 已接收字节数。
  final int receivedBytes;

  /// 当前传输速度（字节/秒）。
  ///
  /// 由下载器在进度回调里按"已接收 / 已耗时"算出。展示用，
  /// 不参与任何判断。
  final int bytesPerSecond;

  /// 已尝试过的次数（含镜像切换与退避重试）。
  final int attempt;

  /// 失败原因。
  final DownloadFailureReason? failureReason;

  /// 给用户看的失败说明，可能包含对象存储返回的错误码。
  final String? message;

  /// 上次下载时是否确认过需要签名。
  ///
  /// 用于下次直接走私有域，省掉三次必然 403 的公开镜像探测。
  final bool requiresAuth;

  /// 落盘路径，成功后填充。
  final String? savePath;

  /// 进度，0~1；平台未给出大小时返回 `null` 表示不确定。
  double? get progress {
    if (expectedBytes <= 0) {
      return null;
    }
    final double value = receivedBytes / expectedBytes;
    return value.clamp(0.0, 1.0);
  }

  /// 是否已终结。
  bool get isTerminal => status.isTerminal;

  /// 是否正在下载。
  bool get isRunning => status == DownloadStatus.running;

  /// 是否可以从当前状态重新入队。
  bool get canRetry =>
      (status == DownloadStatus.failed || status == DownloadStatus.cancelled) &&
      mirrors.isNotEmpty;

  /// 从当前状态重新入队，清空进度与失败信息。
  DownloadTask requeued() => DownloadTask(
    textbookId: textbookId,
    title: title,
    mirrors: mirrors,
    expectedBytes: expectedBytes,
    pageCount: pageCount,
    requiresAuth: requiresAuth,
  );

  /// 开始执行。
  DownloadTask started() => _derive(
    status: DownloadStatus.running,
    receivedBytes: 0,
    attempt: attempt + 1,
  );

  /// 更新进度。
  ///
  /// 状态不是 [DownloadStatus.running] 时原样返回，避免迟到的进度回调
  /// 把已完成的任务改回运行中。
  DownloadTask progressed(int received, {int bytesPerSecond = 0}) {
    if (status != DownloadStatus.running) {
      return this;
    }
    return _derive(receivedBytes: received, bytesPerSecond: bytesPerSecond);
  }

  /// 标记成功。
  DownloadTask succeeded(String savePath) => _derive(
    status: DownloadStatus.completed,
    receivedBytes: expectedBytes > 0 ? expectedBytes : receivedBytes,
    savePath: savePath,
  );

  /// 标记失败。
  DownloadTask failed(DownloadFailureReason reason, String message) => _derive(
    status: DownloadStatus.failed,
    failureReason: reason,
    message: message,
  );

  /// 标记取消。
  DownloadTask cancelled() => _derive(
    status: DownloadStatus.cancelled,
    failureReason: DownloadFailureReason.cancelled,
  );

  /// 标记该教材需要签名。
  DownloadTask withRequiresAuth() => _derive(requiresAuth: true);

  DownloadTask _derive({
    DownloadStatus? status,
    int? receivedBytes,
    int? bytesPerSecond,
    int? attempt,
    DownloadFailureReason? failureReason,
    String? message,
    bool? requiresAuth,
    String? savePath,
  }) => DownloadTask(
    textbookId: textbookId,
    title: title,
    mirrors: mirrors,
    expectedBytes: expectedBytes,
    pageCount: pageCount,
    status: status ?? this.status,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    attempt: attempt ?? this.attempt,
    failureReason: failureReason,
    message: message,
    requiresAuth: requiresAuth ?? this.requiresAuth,
    savePath: savePath,
  );

  /// 只比较身份与状态。
  ///
  /// 进度字段刻意不参与——比较进度没有语义，还会让每次进度更新都触发
  /// 不必要的"已变化"判断。
  @override
  List<Object?> get props => <Object?>[
    textbookId,
    status,
    failureReason,
    attempt,
    savePath,
  ];

  @override
  String toString() =>
      'DownloadTask($title, ${status.name}'
      '${failureReason == null ? '' : ', ${failureReason!.name}'})';
}
