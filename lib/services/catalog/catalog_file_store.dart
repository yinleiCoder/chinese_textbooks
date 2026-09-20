import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';
import 'catalog_manifest.dart';

/// 目录数据在磁盘上的读写。
///
/// 布局见 `AppPaths`。本类只关心"怎么安全地落盘"，
/// 不关心"该不该下载"——那是仓储层的事。
///
/// **所有写入都是原子的**：先写 `.tmp`，再 rename 覆盖。
/// 下载到一半被杀进程、或解析时崩溃，都不会留下半截文件冒充完整数据。
final class CatalogFileStore {
  const CatalogFileStore({required this._paths});

  final AppPaths _paths;

  /// 清单文件。
  File get manifestFile => File(p.join(_paths.catalog.path, 'manifest.json'));

  /// 标签树文件。
  File get tagTreeFile => File(p.join(_paths.catalog.path, 'tags.json'));

  /// 解析后的分片目录。
  Directory get shardDirectory =>
      Directory(p.join(_paths.catalog.path, 'shards'));

  /// 下载中的原始分片暂存区。
  Directory get stagingDirectory => _paths.stagingDirectory;

  /// 某个分片在本地对应的文件名。
  ///
  /// 用 URL 的 SHA-1 前 16 位而不是序号：分片列表的顺序或数量变化时，
  /// 按序号命名会让内容与文件名错位，按 URL 命名则天然稳定，
  /// 也顺带让"这个文件是哪个分片的"可以反查。
  String shardFileNameFor(Uri url) {
    final String hash = sha1.convert(utf8.encode(url.toString())).toString();
    return '${hash.substring(0, 16)}.json';
  }

  /// 某个分片解析结果的存放文件。
  File shardFile(String fileName) =>
      File(p.join(shardDirectory.path, fileName));

  /// 读取清单；不存在或格式不符时返回 `null`。
  Future<CatalogManifest?> readManifest() async {
    if (!manifestFile.existsSync()) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(await manifestFile.readAsString());
      return decoded is Map<String, dynamic>
          ? CatalogManifest.fromJson(decoded)
          : null;
    } on Object {
      // 清单损坏等同于"没有目录数据"，走完整下载流程即可。
      return null;
    }
  }

  /// 写入清单。
  ///
  /// 必须在所有分片都落盘之后再调用——它是"本次可用"的凭据。
  Future<void> writeManifest(CatalogManifest manifest) =>
      _writeAtomic(manifestFile, jsonEncode(manifest.toJson()));

  /// 写入标签树原始 JSON。
  Future<void> writeTagTree(String rawJson) =>
      _writeAtomic(tagTreeFile, rawJson);

  /// 写入某个分片的解析结果。
  Future<void> writeShard(String fileName, String encodedRows) =>
      _writeAtomic(shardFile(fileName), encodedRows);

  /// 清理不在 [keep] 里的分片文件。
  ///
  /// 平台调整分片划分时（增删分片、改编号），旧文件会永远留在磁盘上。
  /// 每次成功更新后调用一次，返回删除的数量。
  Future<int> pruneShards(Set<String> keep) async {
    if (!shardDirectory.existsSync()) {
      return 0;
    }
    int removed = 0;
    await for (final FileSystemEntity entity in shardDirectory.list()) {
      if (entity is! File) {
        continue;
      }
      if (!keep.contains(p.basename(entity.path))) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }

  /// 清空暂存区。
  Future<void> clearStaging() async {
    if (!stagingDirectory.existsSync()) {
      return;
    }
    await for (final FileSystemEntity entity in stagingDirectory.list()) {
      await entity.delete(recursive: true);
    }
  }

  /// 删除全部目录数据。
  Future<void> deleteAll() async {
    for (final FileSystemEntity entity in <FileSystemEntity>[
      manifestFile,
      tagTreeFile,
      shardDirectory,
      stagingDirectory,
    ]) {
      if (entity.existsSync()) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// 目录数据占用的字节数。
  Future<int> usageBytes() => _paths.usageBytes(_paths.catalog);

  /// 原子写入。
  ///
  /// Windows 上 `rename` 到一个已存在的路径会失败，所以必须先删目标。
  /// 删除与重命名之间有极短的窗口期，但此时 `.tmp` 已经完整落盘——
  /// 就算在这个窗口崩了，最坏结果也只是丢一次目录缓存，重新下载即可，
  /// 不会出现半截文件被当成完整数据。
  Future<void> _writeAtomic(File target, String content) async {
    await target.parent.create(recursive: true);
    final File tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (target.existsSync()) {
      await target.delete();
    }
    await tmp.rename(target.path);
  }
}
