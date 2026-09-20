import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../services/storage/storage.dart';
import '../../values/values.dart';
import '../../widgets/widgets.dart';

/// 教材阅读器。
///
/// 用 pdfrx（PDFium 内核）：Windows 与 Android 双端可用，支持文字选中、
/// 全文搜索与手势缩放。它也是本应用唯一一个"必须真机验证"的 native 依赖。
///
/// 阅读进度在**翻页时**落盘，不等到退出——用户很可能直接杀进程，
/// 那时任何"退出时保存"的逻辑都不会执行。
class ReaderPage extends StatefulWidget {
  const ReaderPage({required this.textbookId, super.key, this.title});

  /// 教材 id，同时是本地文件名。
  final String textbookId;

  /// 顶部标题；深链进入时为 `null`。
  final String? title;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final PdfViewerController _controller = PdfViewerController();
  File? _file;
  bool _missing = false;
  int _lastSaved = 0;

  @override
  void initState() {
    super.initState();
    _resolveFile();
    _controller.addListener(_onViewerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onViewerChanged);
    super.dispose();
  }

  /// 定位本地文件。
  ///
  /// 书架的唯一真相是磁盘，因此这里也以文件是否存在为准——
  /// 用户可能在文件管理器里把它删了。
  void _resolveFile() {
    final File file = File(
      '${context.read<AppPaths>().pdfDirectory.path}'
      '${Platform.pathSeparator}${widget.textbookId}.pdf',
    );
    if (file.existsSync()) {
      _file = file;
    } else {
      _missing = true;
    }
  }

  /// 翻页时保存进度。
  void _onViewerChanged() {
    if (!_controller.isReady) {
      return;
    }
    final int? page = _controller.pageNumber;
    if (page == null || page <= 0 || page == _lastSaved) {
      return;
    }
    _lastSaved = page;
    unawaited(
      context.read<LibraryProvider>().saveProgress(widget.textbookId, page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final File? file = _file;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? AppStrings.readerTitle,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: switch ((file, _missing)) {
        (_, true) => const AppEmptyView(
          icon: Icons.insert_drive_file_outlined,
          title: AppStrings.readerFileMissing,
          hint: AppStrings.readerFileMissingHint,
        ),
        (final File f, _) => PdfViewer.file(
          f.path,
          controller: _controller,
          // 从上次读到的地方继续，而不是每次翻回第一页。
          initialPageNumber: _lastSaved > 0 ? _lastSaved : 1,
        ),
        _ => const AppLoadingView(),
      },
    );
  }
}
