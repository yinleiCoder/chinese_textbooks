// 一次性准备工作：预置 pdfrx 所需的 PDFium 二进制。
//
// ## 为什么需要这个脚本
//
// `pdfrx` 通过 `pdfium_dart` 的构建钩子（native assets）在**构建时**从
// `bblanchon/pdfium-binaries` 的 GitHub Release 下载 PDFium（约 4~7 MB）。
// 这一步对网络状况很敏感：GitHub 的 Release 资产走
// `release-assets.githubusercontent.com`，在部分网络环境下会间歇性连不上，
// 表现为构建时抛出 `Failed to download PDFium`（有时被代理包装成 HTTP 404，
// 让人误以为是版本被删——实测该 Release 资产一直存在）。
//
// 该钩子内部有一行 `if (await output.exists()) return;`：**目标文件已存在就跳过下载**。
// 本脚本预先放好二进制，构建便不再依赖那一次网络请求，同时也让离线构建成为可能。
//
// ## 用法
//
// ```bash
// dart run tool/setup_pdfium.dart
// ```
//
// 执行时机：**首次构建前**，以及**每次 `flutter clean` 之后**（clean 会清掉 `.dart_tool`）。
// 脚本幂等，已存在的目标会跳过；只需补某一个平台时用参数指定架构，例如
// `dart run tool/setup_pdfium.dart arm64`。
//
// 脚本自带重试（最多 [_maxAttempts] 次），因为该下载失败多为瞬时现象。

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// PDFium Release 的 tag。
///
/// 与 `pdfium_dart` 内部硬编码的版本保持一致——FFI 绑定就是按这个版本的
/// C API 生成的，用别的版本可能因导出函数增删而在运行时崩溃。
const String _pdfiumRelease = 'chromium/7811';

/// 单个目标的下载重试次数。
const int _maxAttempts = 5;

/// 钩子期望的目录名。
///
/// 注意这里**必须**是 `chromium_7811`——它是 `pdfium_dart` 硬编码的版本号
/// （`_pdfiumRelease.replaceAll('%2F', '_')`）拼出来的路径段。
/// 我们放的二进制实际来自 7869，但路径必须迁就钩子的期望，否则它认不出来。
const String _hookVersionDir = 'chromium_7811';

/// 需要补齐的目标平台。
///
/// 字段对应 `pdfium_dart/hook/build.dart` 里 `_PdfiumTarget` 的取值：
/// 归档文件名是 `pdfium-{archivePlatform}-{archiveArch}.tgz`，
/// 库在归档内的路径是 `archiveLibraryPath`，落地文件名是 `libraryFileName`。
const List<_Target> _targets = <_Target>[
  _Target(
    archivePlatform: 'win',
    archiveArch: 'x64',
    archiveLibraryPath: 'bin/pdfium.dll',
    libraryFileName: 'pdfium.dll',
    label: 'Windows x64',
  ),
  _Target(
    archivePlatform: 'android',
    archiveArch: 'arm64',
    archiveLibraryPath: 'lib/libpdfium.so',
    libraryFileName: 'libpdfium.so',
    label: 'Android arm64-v8a',
  ),
  _Target(
    archivePlatform: 'android',
    archiveArch: 'arm',
    archiveLibraryPath: 'lib/libpdfium.so',
    libraryFileName: 'libpdfium.so',
    label: 'Android armeabi-v7a',
  ),
  _Target(
    archivePlatform: 'android',
    archiveArch: 'x64',
    archiveLibraryPath: 'lib/libpdfium.so',
    libraryFileName: 'libpdfium.so',
    label: 'Android x86_64',
  ),
];

Future<void> main(List<String> args) async {
  final Directory projectRoot = _projectRoot();

  // 只补齐用户显式指定的目标，默认全部。
  final Set<String> only = args.toSet();
  final List<_Target> selected = only.isEmpty
      ? _targets
      : _targets.where((_Target t) => only.contains(t.archiveArch)).toList();

  if (selected.isEmpty) {
    stderr.writeln('没有匹配的目标。可用参数：${_targets.map((t) => t.archiveArch).join(', ')}');
    exitCode = 2;
    return;
  }

  final Directory sharedDir = Directory(
    '${projectRoot.path}${Platform.pathSeparator}.dart_tool'
    '${Platform.pathSeparator}hooks_runner'
    '${Platform.pathSeparator}shared'
    '${Platform.pathSeparator}pdfium_dart'
    '${Platform.pathSeparator}build',
  );

  stdout.writeln('PDFium 来源：$_pdfiumRelease');
  stdout.writeln('目标位置：${sharedDir.path}');
  stdout.writeln('');

  bool allOk = true;
  for (final _Target target in selected) {
    final File output = File(
      '${sharedDir.path}${Platform.pathSeparator}$_hookVersionDir'
      '${Platform.pathSeparator}${target.dirName}'
      '${Platform.pathSeparator}${target.libraryFileName}',
    );

    if (output.existsSync()) {
      stdout.writeln('✓ ${target.label}：已存在，跳过');
      continue;
    }

    stdout.write('… ${target.label}：下载中 ');
    try {
      await _fetch(target, output);
      final double mb = output.lengthSync() / 1024 / 1024;
      stdout.writeln('完成（${mb.toStringAsFixed(1)} MB）');
    } on Object catch (error) {
      stdout.writeln('失败');
      stderr.writeln('  $error');
      allOk = false;
    }
  }

  stdout.writeln('');
  if (allOk) {
    stdout.writeln('全部就绪，现在可以 flutter build / flutter run 了。');
  } else {
    stderr.writeln('部分目标失败。若网络访问 GitHub 受限，请配置代理后重试。');
    exitCode = 1;
  }
}

/// 下载并解出单个目标。
Future<void> _fetch(_Target target, File output) async {
  final Uri uri = Uri.parse(
    'https://github.com/bblanchon/pdfium-binaries/releases/download/'
    '${Uri.encodeComponent(_pdfiumRelease)}/${target.archiveName}',
  );

  Object? lastError;
  for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
    try {
      final List<int> bytes = await _download(uri);
      final Archive archive = TarDecoder().decodeBytes(
        const GZipDecoder().decodeBytes(bytes),
      );
      final ArchiveFile? member = archive.findFile(target.archiveLibraryPath);
      if (member == null) {
        throw const FormatException('归档中找不到目标库文件');
      }
      await output.parent.create(recursive: true);
      await output.writeAsBytes(member.content as List<int>);
      return;
    } on Object catch (error) {
      lastError = error;
      if (attempt < _maxAttempts) {
        // 退避重试：这类失败绝大多数是瞬时的，实测重试一次往往就成功。
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }
  throw HttpException('重试 $_maxAttempts 次仍失败：$lastError');
}

/// 执行一次下载。
Future<List<int>> _download(Uri uri) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'chinese_textbooks-setup');
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}：$uri');
    }
    // 必须 await：否则客户端会在响应体读完之前就被 finally 关掉。
    return await _collect(response);
  } finally {
    client.close();
  }
}

/// 把响应体读成字节数组。
Future<List<int>> _collect(HttpClientResponse response) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// 项目根目录（本脚本位于 `<root>/tool/`）。
Directory _projectRoot() {
  final File script = File.fromUri(Platform.script);
  return script.parent.parent;
}

/// 一个待补齐的目标。
final class _Target {
  const _Target({
    required this.archivePlatform,
    required this.archiveArch,
    required this.archiveLibraryPath,
    required this.libraryFileName,
    required this.label,
  });

  /// 归档文件名里的平台段，如 `win`、`android`。
  final String archivePlatform;

  /// 归档文件名里的架构段，如 `x64`、`arm64`。
  final String archiveArch;

  /// 库在归档内的路径。
  final String archiveLibraryPath;

  /// 落地后的文件名。
  final String libraryFileName;

  /// 给人看的名字。
  final String label;

  /// 归档文件名。
  String get archiveName => 'pdfium-$archivePlatform-$archiveArch.tgz';

  /// 钩子期望的子目录名，形如 `win-x64`。
  String get dirName => '$archivePlatform-$archiveArch';
}
