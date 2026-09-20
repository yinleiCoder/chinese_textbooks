/// 键值存储抽象。
///
/// 这是**依赖倒置**的关键一环：缓存层只依赖这个接口，
/// 而不关心背后是 `shared_preferences`、`flutter_secure_storage`
/// 还是测试里的内存实现。
///
/// 为什么值统一是 [String]：
/// 业务写入的都是结构化数据的序列化结果，字符串是唯一无损的中间表示；
/// 需要存布尔/数字时由调用方决定编码方式，接口不必为每种类型开一个方法，
/// 从而避免实现类被迫实现一堆用不到的方法（接口隔离原则）。
abstract interface class KeyValueStore {
  /// 读取字符串，键不存在时返回 `null`。
  Future<String?> readString(String key);

  /// 写入字符串，已存在则覆盖。
  Future<void> writeString(String key, String value);

  /// 键是否存在。
  Future<bool> containsKey(String key);

  /// 删除单个键，键不存在时静默返回。
  Future<void> delete(String key);

  /// 清空**本存储内**的全部数据。
  ///
  /// 实现方必须保证不会误删其他模块的数据（通常通过键前缀隔离）。
  Future<void> deleteAll();

  /// 列出当前存储中的所有键。
  Future<Set<String>> keys();
}
