import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用私有目录布局。
///
/// ```
/// <ApplicationSupportDirectory>/
/// ├── catalog/                 目录数据（快照与标签树）
/// │   ├── manifest.json        最后写入，"本次可用"的唯一凭据
/// │   ├── v<snapshotId>/       某一版快照
/// │   └── staging/             下载中的分片
/// ├── library/                 已下载的教材
/// │   ├── index.json           下载记录
/// │   └── pdf/<contentId>.pdf
/// └── tmp/                     中间文件，启动时清空
/// ```
///
/// **三者必须在同一个根下**：[AppPaths.library] 与 [AppPaths.tmp] 跨卷时
/// `File.rename` 会退化成"复制 + 删除"，原子性丢失——下载中途崩溃就会留下
/// 半截文件冒充成品。
///
/// 选 `ApplicationSupportDirectory` 而不是 `Documents`：Android 上后者是
/// 用户可见区，会被文件管理器误删；导出功能另行提供，不依赖这个目录。
final class AppPaths {
  const AppPaths._({
    required this.root,
    required this.catalog,
    required this.library,
    required this.tmp,
  });

  /// 解析并创建目录结构。
  ///
  /// 幂等，可以在每次启动时调用。
  static Future<AppPaths> resolve() async {
    final Directory support = await getApplicationSupportDirectory();
    final AppPaths paths = forRoot(Directory(p.join(support.path, 'nd')));
    await paths.ensureCreated();
    return paths;
  }

  /// 用指定根目录构造。
  ///
  /// 供测试与诊断脚本使用——它们跑在没有平台通道的环境里，
  /// 拿不到 `getApplicationSupportDirectory()`。
  static AppPaths forRoot(Directory root) => AppPaths._(
    root: root,
    catalog: Directory(p.join(root.path, 'catalog')),
    library: Directory(p.join(root.path, 'library')),
    tmp: Directory(p.join(root.path, 'tmp')),
  );

  /// 数据根目录。
  final Directory root;

  /// 目录数据（快照、标签树、分片）。
  final Directory catalog;

  /// 已下载教材。
  final Directory library;

  /// 下载中间文件。
  final Directory tmp;

  /// 教材 PDF 的存放目录。
  Directory get pdfDirectory => Directory(p.join(library.path, 'pdf'));

  /// 目录数据中"下载中"的暂存区。
  Directory get stagingDirectory => Directory(p.join(catalog.path, 'staging'));

  /// 创建全部目录。
  Future<void> ensureCreated() async {
    for (final Directory dir in <Directory>[
      root,
      catalog,
      library,
      tmp,
      pdfDirectory,
      stagingDirectory,
    ]) {
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// 清空中间文件目录。
  ///
  /// 每次启动调用。残留的 `.tmp` 无法判断完整性，而第一版不做断点续传，
  /// 留着只会占空间并干扰"文件是否已存在"的判断。
  Future<int> clearTmp() async {
    if (!tmp.existsSync()) {
      return 0;
    }
    int removed = 0;
    await for (final FileSystemEntity entity in tmp.list()) {
      await entity.delete(recursive: true);
      removed++;
    }
    return removed;
  }

  /// 计算某个目录的占用字节数。
  ///
  /// 供设置页展示。遍历整棵树，在几十万个文件以内是可接受的；
  /// 目录数量级远小于此，不做缓存。
  Future<int> usageBytes(Directory directory) async {
    if (!directory.existsSync()) {
      return 0;
    }
    int total = 0;
    await for (final FileSystemEntity entity in directory.list(
      recursive: true,
    )) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  @override
  String toString() => 'AppPaths(${root.path})';
}
