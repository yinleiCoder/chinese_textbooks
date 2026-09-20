/// 本地存储层。
///
/// 对外暴露抽象的 `KeyValueStore` 与两个具体实现
/// （`PreferencesStore` / `SecureStore`），上层只依赖抽象。
library;

export 'app_paths.dart';
export 'key_value_store.dart';
export 'preferences_store.dart';
export 'secure_store.dart';
