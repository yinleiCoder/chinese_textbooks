import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../logger/app_logger.dart';

/// 把已下载的教材导出到用户选定的位置。
///
/// ## 为什么存的是 contentId、导出时才起中文名
///
/// 应用内部一律用 `contentId.pdf` 命名：中文文件名在 Android 的分区存储、
/// Windows 的网络驱动器和各种同步盘上都有编码坑。到了导出这一步——
/// 用户要拿这个文件去别的地方用——才把书名还原出来，并做一次净化。
abstract final class BookExporter {
  /// Windows 保留名。
  ///
  /// 这些名字在 Windows 上无论加什么扩展名都不能作为文件名，
  /// 而教材标题里确实可能出现（例如《CON 的故事》）。
  static const Set<String> _reservedNames = <String>{
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// 文件名里不允许出现的字符。
  static final RegExp _illegalChars = RegExp(r'[<>:"/\|?*\x00-\x1F]');

  /// 单个文件名分量的长度上限。
  ///
  /// 大多数文件系统的上限是 255 字节，而 UTF-8 下一个汉字占 3 字节。
  /// 取 80 个字符留足余量，也给 `.pdf` 和可能的 ` (2)` 后缀留位置。
  static const int _maxNameLength = 80;

  /// 净化书名，得到一个可安全用作文件名的字符串。
  ///
  /// **非法字符替换为全角而不是删除**：书名里的 `:` 换成 `：` 仍然可读，
  /// 直接删掉会让两本不同的书可能变成同一个名字。
  static String sanitize(String title) {
    String name = title
        .replaceAllMapped(_illegalChars, (Match m) => _fullWidthOf(m[0]!))
        .trim()
        // 结尾的点和空格在 Windows 上会被静默丢掉，导致"导出成功但找不到"。
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) {
      name = '未命名教材';
    }
    if (name.length > _maxNameLength) {
      name = name.substring(0, _maxNameLength);
    }
    if (_reservedNames.contains(name.toUpperCase())) {
      name = '_$name';
    }
    return name;
  }

  /// 导出 [source] 到用户选定位置。
  ///
  /// 返回导出的目标路径；用户取消时返回 `null`。
  static Future<String?> export({
    required File source,
    required String title,
    required AppLogger logger,
  }) async {
    try {
      if (!source.existsSync()) {
        logger.w('导出失败：源文件不存在（${source.path}）');
        return null;
      }

      // file_picker 13 的 saveFile 是静态方法且**要求传入字节**，
      // 由它自己完成落盘，返回目标 Uri（用户取消时为 null）。
      final Uri? saved = await FilePicker.saveFile(
        dialogTitle: '导出教材',
        fileName: '${sanitize(title)}.pdf',
        bytes: await source.readAsBytes(),
        mimeType: 'application/pdf',
      );
      if (saved == null) {
        return null;
      }
      // Android 上返回的是 content:// 而不是 file://，不能调 toFilePath()。
      final String location = saved.toString();
      logger.i('已导出：$location');
      return location;
    } on Object catch (error, stackTrace) {
      logger.w('导出失败', error, stackTrace);
      return null;
    }
  }

  /// 非法字符对应的全角写法。
  static String _fullWidthOf(String char) => switch (char) {
    '<' => '＜',
    '>' => '＞',
    ':' => '：',
    '"' => '＂',
    '/' => '／',
    r'\' => '＼',
    '|' => '｜',
    '?' => '？',
    '*' => '＊',
    _ => '',
  };
}
