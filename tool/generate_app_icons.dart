// 一次性准备工作：把图标设计源变成两端能用的图标。
//
// ## 为什么要脚本
//
// 图标的设计源只有 `assets/兔子.svg` 一张矢量图，而两个平台都只认位图；
// 改一次图标要出七八个尺寸，手工作图会很快与源文件脱节，因此固化下来。
//
// 光栅化交给本机的 Chrome / Edge 无头模式，而不是引入图像库：浏览器对 SVG
// 的渲染就是设计稿所见的效果，也不必为一次性任务往项目里加渲染依赖。
//
// ## 为什么只让浏览器画一张，其余尺寸在本地降采样
//
// 无头浏览器连着启动多次会互抢 profile 锁，实测每张图会干等三分钟；
// 而且小窗口（24×24 这种）本身也不稳。既然 1024 那一张已经够清晰，
// 其余尺寸用面积平均降采样即可——这也正是各家图标工具的通行做法。
//
// ## Windows 为什么不走 flutter_launcher_icons
//
// 它的 Windows 分支只能出**单尺寸** .ico——`icon_size` 只接受一个值。只带 256
// 那一张的 .ico，在任务栏 16×16、资源管理器 32×32 上全靠系统硬缩放，明显发糊；
// 而 Flutter 模板自带的 app_icon.ico 本身就是六个尺寸，换上去反倒是退步。
// 所以 .ico 由本脚本按 [_icoSizes] 打包，pubspec 里那份配置只负责 Android。
//
// ## 产出
//
// | 文件 | 用途 |
// | --- | --- |
// | `assets/icons/app_icon.png` | 母图，Windows 各尺寸与 Android mipmap 都从它来 |
// | `windows/runner/resources/app_icon.ico` | Windows 图标，多尺寸 |
//
// ## 用法
//
// ```bash
// dart run tool/generate_app_icons.dart
// dart run flutter_launcher_icons          # 由母图派生 Android 图标
// ```
//
// 执行时机：**图标源改动之后**。产物都进版本库，因此日常构建不需要跑这个脚本。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图标设计源，唯一的事实来源。
const String _sourceSvgPath = 'assets/兔子.svg';

/// 母图。1024 是 `flutter_launcher_icons` 的推荐上限，
/// 也是 .ico 各尺寸降采样的采样源。
const String _masterPath = 'assets/icons/app_icon.png';

/// Windows 图标。
const String _windowsIcoPath = 'windows/runner/resources/app_icon.ico';

/// 母图边长。
const int _masterSize = 1024;

/// .ico 里要放的尺寸。
///
/// 覆盖 Windows 在 100%~200% 缩放下的常见取值：16/24/32/48 是标题栏、
/// 任务栏与资源管理器各视图，128/256 是大图标视图。
const List<int> _icoSizes = <int>[16, 24, 32, 48, 64, 128, 256];

/// 单次渲染的超时上限。
///
/// 无头浏览器偶发地等不到首帧且不退出；不设上限的话脚本会静默卡死，
/// 看不出卡在哪一步。
const Duration _renderTimeout = Duration(minutes: 2);

/// 浏览器可执行文件的候选路径，按优先级排列。
///
/// 无头截图用哪家都行（Chrome 与 Edge 同为 Chromium 内核），这里只是把常见
/// 安装位置列全，避免要求使用者配 PATH。
const List<String> _browserPaths = <String>[
  r'C:\Program Files\Google\Chrome\Application\chrome.exe',
  r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
  r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
  r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
];

/// PATH 中可直接调用的浏览器命令名，作为候选路径的后备。
const List<String> _browserCommands = <String>[
  'google-chrome',
  'chromium',
  'chromium-browser',
  'msedge',
];

Future<void> main() async {
  final File source = File(_absolute(_sourceSvgPath));
  if (!source.existsSync()) {
    _fail('找不到图标源文件：$_sourceSvgPath');
  }

  final String svg = _sanitizeSvg(source.readAsStringSync());
  final String browser = _findBrowser();
  stdout.writeln('使用浏览器：$browser');

  // 无头浏览器的输入必须是文件，用完即删，不留在项目里。
  final Directory scratch = Directory.systemTemp.createTempSync('app_icons_');
  final File master = File(_absolute(_masterPath))
    ..parent.createSync(recursive: true);
  try {
    await _screenshot(
      browser: browser,
      svg: svg,
      scratch: scratch,
      target: master,
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
  stdout.writeln('已生成 $_masterPath（$_masterSize×$_masterSize）');

  final img.Image image = _decode(master.readAsBytesSync());
  final File ico = File(_absolute(_windowsIcoPath))
    ..parent.createSync(recursive: true);
  ico.writeAsBytesSync(_packIco(image));
  stdout.writeln('已生成 $_windowsIcoPath（${_icoSizes.join(' / ')}）');

  stdout.writeln('\nAndroid 图标：dart run flutter_launcher_icons');
}

/// 把相对路径按项目根目录展开。
///
/// 脚本以 `dart run tool/xxx.dart` 执行时工作目录就是项目根，显式展开是为了
/// 在别处调用时同样正确。
String _absolute(String relativePath) => '${Directory.current.path}/$relativePath';

/// 去掉内联进 HTML 后非法的节点。
///
/// XML 声明与 DOCTYPE 出现在 HTML 的 body 里都是非法节点，浏览器遇到会切进
/// 怪异模式；SVG 的其余部分（含 `viewBox` 与 `xmlns`）保持原样即可。
String _sanitizeSvg(String svg) {
  return svg
      .replaceAll(RegExp(r'<\?xml.*?\?>', dotAll: true), '')
      .replaceAll(RegExp(r'<!DOCTYPE.*?>', dotAll: true), '')
      .trim();
}

/// 找到可用于无头截图的浏览器。
String _findBrowser() {
  for (final String path in _browserPaths) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  // PATH 里查命令：Windows 用 `where`、类 Unix 用 `which`，与其分平台判断，
  // 不如直接试着跑一下——`--version` 能通就说明命令可用。
  for (final String command in _browserCommands) {
    if (Process.runSync(command, <String>['--version']).exitCode == 0) {
      return command;
    }
  }
  _fail(
    '未找到 Chrome 或 Edge，无法把 SVG 光栅化成 PNG。\n'
    '请安装其中之一，或把它的可执行文件路径加进脚本的 _browserPaths。',
  );
}

/// 让浏览器把 SVG 满幅画成一张透明底的 PNG。
Future<void> _screenshot({
  required String browser,
  required String svg,
  required Directory scratch,
  required File target,
}) async {
  final File page = File('${scratch.path}/icon.html');
  page.writeAsStringSync('''
<!doctype html><meta charset="utf-8"><style>
html, body {
  margin: 0;
  padding: 0;
  width: ${_masterSize}px;
  height: ${_masterSize}px;
  overflow: hidden;
  background: transparent;
}
svg { display: block; width: ${_masterSize}px; height: ${_masterSize}px; }
</style>$svg
''');

  final Process process = await Process.start(browser, <String>[
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    // 独立用户目录：不指定的话会去抢默认目录的锁，撞上使用者正开着的 Chrome
    // 时会干等很久。
    '--user-data-dir=${scratch.path}/profile',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    // 让截图保留透明背景。不传这个参数拿到的是白底图，
    // 贴到深色任务栏或深色启动器上会露出一圈白边。
    '--default-background-color=00000000',
    // 缩放比固定为 1，否则高分屏上会截出 2 倍图。
    '--force-device-scale-factor=1',
    '--window-size=$_masterSize,$_masterSize',
    '--screenshot=${target.path}',
    page.uri.toString(),
  ]);

  final StringBuffer diagnostics = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(diagnostics.write);
  try {
    await process.exitCode.timeout(_renderTimeout);
  } on TimeoutException {
    process.kill();
    _fail('渲染超时（${_renderTimeout.inSeconds}s），已终止浏览器进程。');
  }

  if (!target.existsSync() || target.lengthSync() == 0) {
    _fail('渲染失败：${target.path}\n$diagnostics');
  }
}

/// 把母图降采样成各尺寸，再打包成多尺寸 .ico。
///
/// ICO 允许一个文件里放多张图，Windows 会按当前 DPI 与显示场景挑最合适的一张，
/// 既不必把小图放大、也不会拿大图硬缩。
Uint8List _packIco(img.Image master) {
  // 目录项的排列惯例是从大到小；第一张直接当底图，其余挂成帧，
  // IcoEncoder 会给每一帧写一条目录项。
  final List<int> sizes = _icoSizes.toList()
    ..sort((int a, int b) => b.compareTo(a));

  final img.Image ico = _resize(master, sizes.first);
  for (final int size in sizes.skip(1)) {
    ico.addFrame(_resize(master, size));
  }
  return img.IcoEncoder().encode(ico);
}

/// 降采样。
///
/// 用面积平均而不是双线性：从 1024 缩到 16 是 64 倍的缩小，
/// 双线性只会取到邻近几个像素，细节会丢成噪点；面积平均把整个源区域
/// 平均掉，缩出来的小图才是稳的。
img.Image _resize(img.Image master, int size) {
  return img.copyResize(
    master,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
}

/// 解码 PNG，顺带在这里集中处理失败分支。
img.Image _decode(Uint8List bytes) {
  final img.Image? decoded = img.decodePng(bytes);
  if (decoded == null) {
    _fail('无法解码浏览器产出的 PNG（${bytes.length} 字节）。');
  }
  return decoded;
}

/// 打印错误并退出，避免把问题留到后面更难定位的地方。
Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
