/// 通用工具层。
///
/// 只依赖 Dart SDK 与纯 Dart 包，**不允许**依赖 `services/`、`providers/`、`widgets/`，
/// 以保证这一层可以被任意模块复用而不产生循环依赖。
///
/// ```dart
/// import 'package:chinese_textbooks/utils/utils.dart';
/// ```
library;

export 'debouncer.dart';
export 'extensions/extensions.dart';
export 'failure.dart';
export 'format.dart';
export 'preview_url.dart';
export 'result.dart';
