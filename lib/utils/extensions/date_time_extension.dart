import 'package:intl/intl.dart';

/// 日期时间格式化。
///
/// 依赖 `intl` 的 [DateFormat]，调用前需在启动阶段执行
/// `initializeDateFormatting()` 并设置 `Intl.defaultLocale`，
/// 详见 `services/app_bootstrap.dart`。
extension DateTimeX on DateTime {
  /// 仅日期，`2026-09-19`。
  String get ymd => format('yyyy-MM-dd');

  /// 仅时间，`14:05`。
  String get hm => format('HH:mm');

  /// 日期 + 时间，`2026-09-19 14:05`。
  String get ymdhm => format('yyyy-MM-dd HH:mm');

  /// 中文日期，`2026年9月19日`。
  String get ymdCn => format('yyyy年M月d日');

  /// 星期几，`星期五`。
  String get weekdayCn => format('EEEE');

  /// 按 [pattern] 格式化。
  ///
  /// 每次调用都会新建 [DateFormat]，高频场景请在外部缓存实例。
  String format(String pattern) => DateFormat(pattern).format(this);

  /// 是否为今天。
  bool get isToday {
    final DateTime now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// 是否为昨天。
  bool get isYesterday {
    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }

  /// 去掉时分秒，只保留日期部分。
  DateTime get dateOnly => DateTime(year, month, day);

  /// 相对当前时间的口语化描述。
  ///
  /// 规则：一分钟内"刚刚"、一小时内按分钟、一天内按小时、
  /// 昨天、一周内按天，再往前直接给日期。
  String get friendly {
    final Duration diff = DateTime.now().difference(this);
    if (diff.isNegative) {
      return ymdhm;
    }
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    }
    if (isYesterday) {
      return '昨天 $hm';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    }
    return ymd;
  }
}

/// 时长格式化。
extension DurationX on Duration {
  /// 秒数转 `mm:ss`，用于音视频进度展示。
  String get mmss {
    final int minutes = inMinutes.remainder(60);
    final int seconds = inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 秒数转 `hh:mm:ss`，超过一小时时自动补出小时位。
  String get hhmmss {
    final int hours = inHours;
    final int minutes = inMinutes.remainder(60);
    final int seconds = inSeconds.remainder(60);
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$mm:$ss'
        : '$mm:$ss';
  }
}
