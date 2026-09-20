import 'package:flutter/material.dart';
// `SliverConstraints` 只在 rendering 里，material 没有转出。
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/providers.dart';
import '../../services/export/export.dart';
import '../../services/logger/app_logger.dart';
import '../../services/router/app_routes.dart';
import '../../utils/utils.dart';
import '../../values/values.dart';
import '../../widgets/widgets.dart';

/// 书架（首页）。
///
/// ## 为什么用 Sliver
///
/// 顶部要同时承载"书名 + 藏书量"和"选择"入口，滚动时还得留在视野里。
/// 用 `Scaffold` + `AppBar` + 独立网格的话，顶部栏与内容是两个滚动体系，
/// 高度一变就会互相挤。`CustomScrollView` 把所有东西放进同一条滚动轴，
/// 布局关系是确定的。
///
/// ## 选择模式
///
/// 平时点书是"打开"，进入选择模式后点书变成"勾选"——相册与文件管理器的
/// 通行做法。只有这时底部才出现多选操作条，平时不占地方。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _knownCompleted = -1;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    context.read<LibraryProvider>().load(
      index: context.read<CatalogProvider>().index,
    );
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selected.remove(id)) {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DownloadProvider downloads = context.watch<DownloadProvider>();
    final LibraryProvider library = context.watch<LibraryProvider>();

    // 下载完成数变了就重扫一次。用计数而不是监听每个任务，
    // 是为了避免进度事件把书架也带着重建。
    final int completed = downloads.completedIds.length;
    if (completed != _knownCompleted) {
      _knownCompleted = completed;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          _AppBar(
            count: library.count,
            selectionMode: _selectionMode,
            selectedCount: _selected.length,
            allSelected: library.count > 0 && _selected.length == library.count,
            onToggleMode: () => setState(() {
              if (_selectionMode) {
                _exitSelection();
              } else {
                _selectionMode = true;
              }
            }),
            onSelectAll: library.isEmpty
                ? null
                : () => _toggleSelectAll(library),
          ),
          if (library.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyView(
                icon: Icons.auto_stories_outlined,
                title: AppStrings.libraryEmptyTitle,
                hint: AppStrings.libraryEmptyHint,
              ),
            )
          else
            ..._shelfSlivers(library.sections),
        ],
      ),
      bottomNavigationBar: _selectionMode
          ? _SelectionActions(selected: _selected, onDone: _exitSelection)
          : null,
    );
  }

  /// 把分区摊成一串 sliver。
  ///
  /// 每个分区是"表头 + 一片网格"。用多片网格而不是在一个网格里插表头，
  /// 是因为表头一旦作为网格的一项，就会占掉一整行的位置，把书挤到下一行去、
  /// 在表头旁边留下一块空白。
  List<Widget> _shelfSlivers(List<LibrarySection> sections) {
    // 「未分组」要不要表头，取决于整个书架有没有真的分组：一个分组都没有时，
    // 给所有书加一个"未分组"表头只是噪音——那本来就是没有分组概念的那张老书架。
    final bool divided = sections.any(
      (LibrarySection section) => section.kind == LibrarySectionKind.group,
    );

    final List<Widget> slivers = <Widget>[];
    for (int i = 0; i < sections.length; i++) {
      final LibrarySection section = sections[i];
      final bool titled =
          section.kind != LibrarySectionKind.ungrouped || divided;
      final bool last = i == sections.length - 1;
      // 没有表头时，网格自己顶上分区的上边距。
      final double gridTop = titled
          ? 0
          : (i == 0 ? AppDimens.gapSm : AppDimens.gapLg);

      if (titled) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppDimens.gapMd,
              i == 0 ? AppDimens.gapSm : AppDimens.gapLg,
              AppDimens.gapMd,
              AppDimens.gapXs,
            ),
            sliver: SliverToBoxAdapter(
              child: _SectionHeader(
                label: _sectionLabel(section),
                count: section.books.length,
              ),
            ),
          ),
        );
      }

      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppDimens.gapSm,
            gridTop,
            AppDimens.gapSm,
            last ? AppDimens.gapXl : 0,
          ),
          sliver: SliverLayoutBuilder(
            builder: (BuildContext context, SliverConstraints constraints) {
              // 列数直接按可用宽度算，而不是交给
              // `SliverGridDelegateWithMaxCrossAxisExtent` 去"取整"：
              // 360dp 的手机上可用宽度 336，336 / (320 + 16) 正好是 1.0，
              // 向上取整得到 **1 列**——书架在手机上一列一条，翻起来没完。
              // 这里手机上恒为 2 列（每列约 160），桌面端按 240 一列往外加
              // （1200 的窗口仍是 4 列，与过去一致），书封尺寸不会被拉飞。
              final int columns = (constraints.crossAxisExtent / 240)
                  .round()
                  .clamp(2, 6);
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 20,
                ),
                itemCount: section.books.length,
                itemBuilder: (BuildContext context, int index) {
                  final LibraryBook book = section.books[index];
                  return _BookCard(
                    book: book,
                    selectionMode: _selectionMode,
                    selected: _selected.contains(book.id),
                    onTap: () => _onBookTap(book),
                    onLongPress: () => setState(() {
                      _selectionMode = true;
                      _selected.add(book.id);
                    }),
                    onShowActions: () => _showBookActions(book),
                  );
                },
              );
            },
          ),
        ),
      );
    }
    return slivers;
  }

  /// 分区的标题。
  ///
  /// 「置顶」「未分组」是界面文案，分组名才是用户数据——所以只有后者取自模型。
  String _sectionLabel(LibrarySection section) => switch (section.kind) {
    LibrarySectionKind.pinned => AppStrings.libraryPin,
    // group 区一定有名字：它是由 assignGroup 写入分组名才存在的。
    LibrarySectionKind.group => section.title ?? '',
    LibrarySectionKind.ungrouped => AppStrings.libraryUngrouped,
  };

  void _onBookTap(LibraryBook book) {
    if (_selectionMode) {
      _toggleSelection(book.id);
      return;
    }
    context.pushNamed(
      AppRoutes.readerName,
      pathParameters: <String, String>{'id': book.id},
      extra: book.title,
    );
  }

  void _toggleSelectAll(LibraryProvider library) {
    setState(() {
      final Set<String> all = library.books
          .map((LibraryBook b) => b.id)
          .toSet();
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  /// 单本的长按菜单（不在选择模式下时用）。
  Future<void> _showBookActions(LibraryBook book) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text(AppStrings.readerExport),
              onTap: () => Navigator.of(sheetContext).pop('export'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text(AppStrings.readerRemove),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'remove') {
      await _confirmRemove(context, <LibraryBook>[book]);
      return;
    }
    final String? location = await BookExporter.export(
      source: book.file,
      title: book.title,
      logger: context.read<AppLogger>(),
    );
    if (mounted) {
      context.showSnackBar(
        location == null
            ? AppStrings.readerExportFailed
            : AppStrings.readerExported(location),
      );
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    List<LibraryBook> targets,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(AppStrings.libraryRemoveConfirmTitle(targets.length)),
        content: const Text(AppStrings.libraryRemoveConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await context.read<LibraryProvider>().removeMany(
      targets.map((LibraryBook b) => b.id).toSet(),
    );
    if (context.mounted) {
      _exitSelection();
    }
  }
}

/// 顶部栏：书名、藏书量、选择入口。
class _AppBar extends StatelessWidget {
  const _AppBar({
    required this.count,
    required this.selectionMode,
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleMode,
    required this.onSelectAll,
  });

  final int count;
  final bool selectionMode;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onToggleMode;
  final VoidCallback? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SliverAppBar(
      pinned: true,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            selectionMode
                ? AppStrings.selectedCount(selectedCount)
                : AppStrings.tabLibrary,
          ),
          // 藏书量放在标题下面一行小字里，而不是另起一条横幅——
          // 它只是背景信息，不该和"选择"这类操作抢视线。
          if (!selectionMode && count > 0)
            Text(
              AppStrings.libraryCount(count),
              style: TextStyle(
                fontSize: AppDimens.fontCaption,
                fontWeight: FontWeight.w400,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: <Widget>[
        if (count > 0) ...<Widget>[
          if (selectionMode)
            TextButton(
              onPressed: onSelectAll,
              child: Text(
                allSelected ? AppStrings.clearSelection : AppStrings.selectAll,
              ),
            ),
          TextButton(
            onPressed: onToggleMode,
            child: Text(
              selectionMode ? AppStrings.done : AppStrings.select,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 选择模式下的底部操作条。
class _SelectionActions extends StatelessWidget {
  const _SelectionActions({required this.selected, required this.onDone});

  final Set<String> selected;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final LibraryProvider library = context.read<LibraryProvider>();
    final bool enabled = selected.isNotEmpty;
    // 选中的书全都已置顶时，这一下按下去是"取消置顶"。按钮文字必须跟着变——
    // 否则按钮写着"置顶"、书却已经置顶了，用户只能靠试错去猜它的意思。
    // 判断口径与 LibraryProvider.togglePin 一致：全置顶则取消，否则一并置顶。
    final bool allPinned = enabled && selected.every(library.isPinned);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppDimens.gapXxs),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _action(
                  icon: allPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  label: allPinned
                      ? AppStrings.libraryUnpin
                      : AppStrings.libraryPin,
                  enabled: enabled,
                  onTap: () => library.togglePin(selected),
                ),
                _action(
                  icon: Icons.folder_outlined,
                  label: AppStrings.libraryGroup,
                  enabled: enabled,
                  onTap: () => _assignGroup(context),
                ),
                _action(
                  icon: Icons.ios_share_rounded,
                  label: AppStrings.libraryShare,
                  enabled: enabled,
                  onTap: () => _share(context),
                ),
                _action(
                  icon: Icons.delete_outline_rounded,
                  label: AppStrings.libraryRemove,
                  enabled: enabled,
                  onTap: () => _remove(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppDimens.gapXs),
      child: TextButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: AppDimens.iconSm),
        label: Text(label),
      ),
    );
  }

  /// 分组：选已有分组，或新建一个。
  ///
  /// 对话框的内容抽成独立的 [StatefulWidget]（见 `_GroupDialog`），
  /// **不是**为了好看：`TextEditingController` 必须由对话框自己持有并释放。
  /// 若在调用方 `await showDialog(...)` 之后就 `dispose()`，那时弹窗还在
  /// 播退场动画、`TextField` 仍然挂在 controller 上——是典型的"用后释放"，
  /// 而 `autofocus` 会放大这个问题。
  Future<void> _assignGroup(BuildContext context) async {
    final LibraryProvider library = context.read<LibraryProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final String? group = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _GroupDialog(groupNames: library.groupNames),
    );
    if (group == null) {
      return;
    }

    final String message = group.trim().isEmpty
        ? AppStrings.libraryGroupRemoved
        : AppStrings.libraryGrouped(group, selected.length);

    await library.assignGroup(selected, group);
    onDone();
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 分享选中的教材。
  Future<void> _share(BuildContext context) async {
    final LibraryProvider library = context.read<LibraryProvider>();
    final List<LibraryBook> targets = library.books
        .where((LibraryBook b) => selected.contains(b.id))
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: targets.map((LibraryBook b) => XFile(b.file.path)).toList(),
        // 分享多份时用书名当标题会很长，给一句概括性的。
        subject: targets.length == 1
            ? targets.first.title
            : AppStrings.libraryShareSubject(targets.length),
      ),
    );
    onDone();
  }

  Future<void> _remove(BuildContext context) async {
    final LibraryProvider library = context.read<LibraryProvider>();
    final List<LibraryBook> targets = library.books
        .where((LibraryBook b) => selected.contains(b.id))
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(AppStrings.libraryRemoveConfirmTitle(targets.length)),
        content: const Text(AppStrings.libraryRemoveConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await library.removeMany(selected);
    onDone();
  }
}

/// 分区表头：分组名 + 本数。
///
/// 本数放在右端而不是跟在名字后面：分组名长短不一，紧跟着写会让各区的
/// 数字参差不齐，右对齐才能一眼扫下来比较。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppDimens.fontSubtitle,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ),
        SizedBox(width: AppDimens.gapXs),
        Text(
          AppStrings.librarySectionCount(count),
          style: TextStyle(
            fontSize: AppDimens.fontCaption,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 书架上的一本书：封面在上、标题在下。
class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onShowActions,
  });

  final LibraryBook book;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? cover = book.coverUrl;
    final String? group = book.group;
    final int? page = book.page;

    // 内边距要放在 InkWell **里面**：这样整张卡片（含四周留白）都是
    // 点击与 hover 的热区。放在外面的话高亮只会框住封面和标题本身。
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onShowActions,
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      child: Padding(
        padding: EdgeInsets.all(AppDimens.gapXs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: cover == null
                        ? _coverPlaceholder(context)
                        : AppNetworkImage(
                            url: cover,
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusSm,
                            ),
                          ),
                  ),
                  if (book.pinned)
                    const Positioned(
                      left: 4,
                      top: 4,
                      child: _Chip(
                        icon: Icons.push_pin_rounded,
                        label: '',
                        color: Color(0xCC2B5C8A),
                      ),
                    ),
                  if (group != null)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: _Chip(
                        icon: Icons.folder_rounded,
                        label: group,
                        color: scheme.secondary.withValues(alpha: 0.85),
                      ),
                    ),
                  if (page != null && !selectionMode)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: _Chip(
                        icon: null,
                        label: AppStrings.readerPageBadge(page),
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                    ),
                  if (selectionMode)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: AppDimens.iconMd,
                        color: selected ? scheme.primary : Colors.white,
                        shadows: const <Shadow>[
                          Shadow(blurRadius: 4, color: Colors.black45),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: AppDimens.gapXs),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDimens.fontCaption,
                height: AppDimens.lineHeightNormal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: AppDimens.iconLg,
          color: scheme.outline,
        ),
      ),
    );
  }
}

/// 封面上的小角标。
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData? icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final IconData? icon = this.icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null)
              Icon(icon, size: AppDimens.fontCaption, color: Colors.white),
            if (icon != null && label.isNotEmpty) const SizedBox(width: 2),
            if (label.isNotEmpty)
              ConstrainedBox(
                // 分组名可能很长，角标不能撑破封面。
                constraints: const BoxConstraints(maxWidth: 64),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDimens.fontCaption,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 分组对话框。
///
/// 作为一个真正的 [StatefulWidget] 存在，是为了让 [TextEditingController]
/// 的生命周期与弹窗**严格一致**：弹窗挂载时创建、彻底卸载时释放。
/// 交给调用方跨越 `await` 去管，就会在退场动画期间释放掉仍在使用的 controller。
class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.groupNames});

  final List<String> groupNames;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // 没输入就不放行。早先这一下会返回空串，而空串的语义是"移出分组"——
    // 用户想新建分组却什么都没发生。
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text(AppStrings.libraryGroupTitle),
      content: SizedBox(
        // 不给宽度的话，AlertDialog 的固有宽度会退化成"内容想要多宽"，
        // 输入框会被压成一条线。
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.groupNames.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: AppDimens.gapXs),
                  child: Text(
                    AppStrings.libraryGroupEmpty,
                    style: TextStyle(
                      fontSize: AppDimens.fontBodySmall,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // 用 SimpleDialogOption 而不是 ListTile：AlertDialog 会给内容
              // 套一层 IntrinsicWidth，ListTile 在固有尺寸测量下不可靠。
              for (final String name in widget.groupNames)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(name),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.folder_outlined),
                      SizedBox(width: AppDimens.gapSm),
                      Expanded(
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: AppDimens.gapSm),
              TextField(
                controller: _controller,
                autofocus: widget.groupNames.isEmpty,
                decoration: const InputDecoration(
                  hintText: AppStrings.libraryGroupNewHint,
                ),
                onSubmitted: (String _) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        if (widget.groupNames.isNotEmpty)
          TextButton(
            // 空串表示"移出分组"，与"取消对话框"（null）区分开。
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text(AppStrings.libraryGroupRemove),
          ),
        FilledButton(
          onPressed: _submit,
          child: const Text(AppStrings.confirm),
        ),
      ],
    );
  }
}
