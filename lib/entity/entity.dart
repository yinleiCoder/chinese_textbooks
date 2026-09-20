/// 数据实体层。
///
/// 这里只放**纯数据模型**：字段、序列化、值相等语义。三条约束：
/// - 不依赖 `flutter`，保证可以被纯 Dart 测试直接构造；
/// - 不依赖 `dio`、`shared_preferences` 等具体实现；
/// - 不写业务逻辑（计算、校验、格式化），那些属于 `utils/` 或状态层。
///
/// 实体用 `json_serializable` 生成序列化代码，
/// 生成命令见根目录 `build.yaml`：
/// ```bash
/// dart run build_runner build
/// ```
library;

export 'catalog_node.dart';
export 'download_task.dart';
export 'nd_credential.dart';
export 'textbook.dart';
export 'textbook_detail.dart';
