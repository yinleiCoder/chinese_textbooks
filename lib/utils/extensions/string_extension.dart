/// 字符串判空与截断辅助。
///
/// 中文语境下 `''` 与 `'   '` 都应当被视为"没填"，
/// 因此这里统一按 [String.trim] 之后的结果判断，避免各处重复写 `trim().isEmpty`。
extension StringX on String {
  /// 去除首尾空白后是否为空。
  bool get isBlank => trim().isEmpty;

  /// 去除首尾空白后是否非空。
  bool get isNotBlank => !isBlank;

  /// 空白字符串转为 `null`，便于统一走"未填写"分支。
  String? get nullIfBlank => isBlank ? null : this;

  /// 按字符截断，超出部分用 [ellipsis] 替代。
  ///
  /// 使用 `characters` 之外的手写实现会有代理对（emoji）截断问题，
  /// 这里通过 `runes` 按码位切分，保证不会把字符切成两半。
  String truncate(int maxLength, {String ellipsis = '…'}) {
    assert(maxLength > 0, 'maxLength 必须为正数');
    final List<int> runes = this.runes.toList();
    if (runes.length <= maxLength) {
      return this;
    }
    return '${String.fromCharCodes(runes.take(maxLength))}$ellipsis';
  }

  /// 隐藏中间部分，用于手机号、身份证等敏感信息展示。
  ///
  /// 例如 `13812345678` 以 `head: 3, tail: 4` 处理后得到 `138****5678`。
  String mask({int head = 3, int tail = 4, String maskChar = '*'}) {
    final int length = runes.length;
    if (length <= head + tail) {
      return this;
    }
    final int maskLength = length - head - tail;
    return '${substring(0, head)}${maskChar * maskLength}${substring(length - tail)}';
  }
}

/// 可空字符串的判空辅助。
extension NullableStringX on String? {
  /// 为 `null` 或空白。
  bool get isNullOrBlank => this == null || this!.isBlank;

  /// 非 `null` 且非空白。
  bool get isNotNullOrBlank => !isNullOrBlank;
}
