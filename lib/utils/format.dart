/// 把字节数格式化成可读文本。
///
/// 放在这里而不是各页面各写一份：设置页的"占用空间"、下载页的"已下载"
/// 与"速度"都要用，口径必须一致，否则同一个数字在两处显示得不一样。
String formatBytes(num bytes, {int fractionDigits = 1}) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : fractionDigits)} ${units[unit]}';
}

/// 把速度格式化成「2.4 MB/s」。
String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';
