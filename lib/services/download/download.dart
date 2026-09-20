/// 下载层。
///
/// 只依赖 `dart:io` + dio + logger，**不依赖 Flutter**，因此可以脱离
/// widget 树单测。通知界面的事交给 `providers/DownloadProvider`。
///
/// 职责划分：
/// - `RequestGate`：并发上限 + 最小发起间隔，两个约束必须同时生效；
/// - `MirrorPlanner`：按登录态决定"先试公开镜像还是直接走私有域"；
/// - `DownloadManager`：队列、重试、落盘、状态机。
library;

export 'download_manager.dart';
export 'mirror_planner.dart';
export 'request_gate.dart';
