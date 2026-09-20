import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../entity/entity.dart';
import '../services/catalog/catalog.dart';
import '../services/logger/app_logger.dart';
import '../services/storage/app_paths.dart';
import '../services/storage/key_value_store.dart';
import '../values/values.dart';

/// 书架上的一本书。
final class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.file,
    this.textbook,
    this.page,
    this.pinned = false,
    this.group,
  });

  /// 教材 id（文件名即 contentId）。
  final String id;

  /// 本地 PDF 文件。
  final File file;

  /// 清单里的条目；目录数据被清理后可能为 `null`。
  final Textbook? textbook;

  /// 上次读到的页码，从 1 起。
  final int? page;

  /// 是否置顶。
  final bool pinned;

  /// 所属分组名。
  final String? group;

  /// 展示用标题。
  String get title => textbook?.title ?? file.uri.pathSegments.last;

  /// 封面地址。
  String? get coverUrl => textbook?.previewUrl;
}

/// 书架上一"区"的类别。
///
/// 分区的意义是把散落的书**归到一起**：同一组的书在书架上连成一片，
/// 而不是各自排在按书名排序的长队里、只在封面上挂一枚标签。
enum LibrarySectionKind {
  /// 置顶区。这里面的书不再出现在它所属的分组里。
  pinned,

  /// 用户建的分组，名字见 [LibrarySection.title]。
  group,

  /// 既没置顶、也没归组的书。
  ungrouped,
}

/// 书架的一个分区：一段连续的、带标题的书。
final class LibrarySection {
  const LibrarySection({required this.kind, required this.books, this.title});

  /// 这一区是什么。
  final LibrarySectionKind kind;

  /// 分组名，只有 [LibrarySectionKind.group] 有。
  ///
  /// 「置顶」「未分组」这两个标题属于界面文案，由页面从 `values/app_strings.dart`
  /// 取——provider 不碰多语言，这里也就只带用户自己输入的分组名。
  final String? title;

  /// 区内的书，按书名排序。
  final List<LibraryBook> books;
}

/// 书架上的**用户组织信息**（置顶与分组）。
///
/// 与文件本身分开存：文件在磁盘上，这份是"用户怎么看它们"。
/// 丢了不影响读书，只是排序与分组回到默认。
final class LibraryArrangement {
  const LibraryArrangement({
    this.pinnedIds = const <String>{},
    this.groupOf = const <String, String>{},
    this.groupOrder = const <String>[],
  });

  /// 置顶的教材 id。
  final Set<String> pinnedIds;

  /// 教材 id → 分组名。
  final Map<String, String> groupOf;

  /// 分组名的创建顺序。
  ///
  /// 不用字典序：中文按 UTF-16 码位排，在用户看来接近随机。
  /// 这张表是**冗余**的——某个名字算不算分组，始终以 [groupOf] 里有没有书
  /// 引用它为准，这里只回答"它排第几"。因此没有书的分组不会出现在书架上，
  /// 也不占位置。
  final List<String> groupOrder;

  /// 现有的分组名，按创建顺序。
  ///
  /// 顺序表里没有的名字排到最后：老版本写入的数据没有这张表，
  /// 不该因为缺一条顺序记录就把分组弄丢。
  List<String> get groupNames {
    final Set<String> live = groupOf.values.toSet();
    final List<String> ordered = <String>[
      for (final String name in groupOrder)
        if (live.contains(name)) name,
    ];
    return <String>[
      ...ordered,
      for (final String name in live)
        if (!ordered.contains(name)) name,
    ];
  }

  /// 更新分组归属，并顺带维护顺序表。
  ///
  /// [created] 是本次新建的分组名，排到末尾；已经没有书的分组名会被裁掉，
  /// 免得弃用的名字一直占着位置。已存在的分组保持原位。
  LibraryArrangement withGroups(
    Map<String, String> groupOf, {
    String? created,
  }) {
    final Set<String> live = groupOf.values.toSet();
    final List<String> order = <String>[
      for (final String name in groupNames)
        if (live.contains(name)) name,
    ];
    if (created != null && !order.contains(created)) {
      order.add(created);
    }
    return copyWith(groupOf: groupOf, groupOrder: order);
  }

  LibraryArrangement copyWith({
    Set<String>? pinnedIds,
    Map<String, String>? groupOf,
    List<String>? groupOrder,
  }) => LibraryArrangement(
    pinnedIds: pinnedIds ?? this.pinnedIds,
    groupOf: groupOf ?? this.groupOf,
    groupOrder: groupOrder ?? this.groupOrder,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'pinned': pinnedIds.toList(),
    'groups': groupOf,
    'groupOrder': groupOrder,
  };

  static LibraryArrangement fromJson(Map<String, dynamic> json) {
    final Object? pinned = json['pinned'];
    final Object? groups = json['groups'];
    final Object? order = json['groupOrder'];
    return LibraryArrangement(
      pinnedIds: pinned is List
          ? pinned.whereType<String>().toSet()
          : const <String>{},
      groupOf: groups is Map<String, dynamic>
          ? <String, String>{
              for (final MapEntry<String, dynamic> e in groups.entries)
                if (e.value is String && (e.value as String).isNotEmpty)
                  e.key: e.value as String,
            }
          : const <String, String>{},
      groupOrder: order is List
          ? order.whereType<String>().toList()
          : const <String>[],
    );
  }
}

/// 书架与阅读进度。
///
/// 书架的**唯一真相是磁盘**：`library/pdf/` 目录下有哪些 `.pdf`。
/// 不另存一份文件清单，是为了避免"索引说在、文件已删"这类不一致——
/// 用户完全可能在文件管理器里手动删掉文件。
///
/// 阅读进度、置顶与分组则必须持久化：它们没有其他真相来源。
final class LibraryProvider extends ChangeNotifier {
  LibraryProvider({
    required this._paths,
    required this._store,
    required this._logger,
  });

  final AppPaths _paths;
  final KeyValueStore _store;
  final AppLogger _logger;

  List<LibraryBook> _books = const <LibraryBook>[];
  final Map<String, int> _progress = <String, int>{};

  /// 最近一次拿到的目录索引。
  ///
  /// **必须记住它。** 书名与封面只有目录里有（磁盘上只有文件名），
  /// 而删除、置顶、分组之后的重新扫描是内部触发的、拿不到调用方的
  /// `index`——不记住的话，那一扫会把所有书的元数据抹成 null，
  /// 表现成"删了一本之后全部书名变成乱码、封面全没了"。
  CatalogIndex? _index;
  LibraryArrangement _arrangement = const LibraryArrangement();
  bool _loaded = false;

  /// 书架上的书，按书名排序的平铺列表。
  ///
  /// 只给"对全库操作"的场景用：全选、分享、移出书架。**书架怎么摆**
  /// 由 [sections] 决定——置顶与分组只在那里体现，这里是一视同仁的。
  List<LibraryBook> get books => _books;

  /// 是否已加载过一次。
  bool get isLoaded => _loaded;

  /// 是否空空如也。
  bool get isEmpty => _books.isEmpty;

  /// 教材总数。
  int get count => _books.length;

  /// 现有的分组名，按创建顺序。
  List<String> get groupNames => _arrangement.groupNames;

  /// 书架的分区：置顶区 → 各分组（按创建顺序）→ 未分组。
  ///
  /// 每本书只出现在一区里。置顶的书**不再出现在它的分组里**——置顶表达的是
  /// "随时要用"，让它同时出现在两处只会让书架看起来像重复了；它属于哪个分组
  /// 仍然记着，封面上的分组角标照常显示。
  ///
  /// 不返回空区：没有书的分组不占位置。
  List<LibrarySection> get sections {
    final List<LibraryBook> pinned = <LibraryBook>[];
    final Map<String, List<LibraryBook>> byGroup =
        <String, List<LibraryBook>>{};
    final List<LibraryBook> loose = <LibraryBook>[];

    for (final LibraryBook book in _books) {
      final String? group = book.group;
      if (book.pinned) {
        pinned.add(book);
      } else if (group != null) {
        byGroup.putIfAbsent(group, () => <LibraryBook>[]).add(book);
      } else {
        loose.add(book);
      }
    }

    return <LibrarySection>[
      if (pinned.isNotEmpty)
        LibrarySection(
          kind: LibrarySectionKind.pinned,
          books: _byTitle(pinned),
        ),
      for (final String name in groupNames)
        if (byGroup[name] case final List<LibraryBook> books?)
          LibrarySection(
            kind: LibrarySectionKind.group,
            title: name,
            books: _byTitle(books),
          ),
      if (loose.isNotEmpty)
        LibrarySection(
          kind: LibrarySectionKind.ungrouped,
          books: _byTitle(loose),
        ),
    ];
  }

  /// 就地按书名排序。
  ///
  /// 传进来的都是 [sections] 里现攒的临时列表，就地排不会影响 [_books]。
  static List<LibraryBook> _byTitle(List<LibraryBook> books) =>
      books..sort((LibraryBook a, LibraryBook b) => a.title.compareTo(b.title));

  /// 这本是否已置顶。
  bool isPinned(String textbookId) =>
      _arrangement.pinnedIds.contains(textbookId);

  /// 这本属于哪个分组。
  String? groupOf(String textbookId) => _arrangement.groupOf[textbookId];

  /// 这本教材是否已经在本地。
  ///
  /// **以磁盘为准，不看内存里的任务表**：任务表在一次会话结束后就没了，
  /// 而文件还在。只查任务表会导致重启后把已下载的书再下一遍。
  bool isDownloaded(String textbookId) =>
      File(
        '${_paths.pdfDirectory.path}'
        '${Platform.pathSeparator}$textbookId.pdf',
      ).existsSync();

  /// 阅读进度的存储键。
  static String progressKey(String textbookId) =>
      '${StorageKeys.readingProgress}$textbookId';

  /// 加载书架与进度。
  ///
  /// [index] 用来补齐书名与封面；目录尚未就绪时传 `null`，
  /// 书架仍然可用，只是显示文件名。
  Future<void> load({CatalogIndex? index}) async {
    _index = index ?? _index;
    await _loadProgress();
    await _loadArrangement();
    await refresh(index: index);
  }

  /// 重新扫描磁盘。
  Future<void> refresh({CatalogIndex? index}) async {
    _index = index ?? _index;
    try {
      final Directory dir = _paths.pdfDirectory;
      final List<LibraryBook> books = <LibraryBook>[];
      if (dir.existsSync()) {
        await for (final FileSystemEntity entity in dir.list()) {
          if (entity is! File || !entity.path.endsWith('.pdf')) {
            continue;
          }
          final String id = _idOf(entity);
          books.add(
            LibraryBook(
              id: id,
              file: entity,
              textbook: _index?.byId(id),
              page: _progress[id],
              pinned: _arrangement.pinnedIds.contains(id),
              group: _arrangement.groupOf[id],
            ),
          );
        }
      }
      // 一律按书名。置顶与分组不在这里排——它们由 sections 表达，
      // 两处都排的话，"谁说了算"就看不清了。
      books.sort((LibraryBook a, LibraryBook b) => a.title.compareTo(b.title));
      _books = books;
      _loaded = true;
    } on Object catch (error, stackTrace) {
      _logger.w('扫描书架失败', error, stackTrace);
      _books = const <LibraryBook>[];
    }
    notifyListeners();
  }

  /// 记录阅读位置。
  ///
  /// 只在**页码变化**时落盘，避免同一页反复触发滚动回调时把存储写爆。
  Future<void> saveProgress(String textbookId, int page) async {
    if (_progress[textbookId] == page) {
      return;
    }
    _progress[textbookId] = page;
    try {
      await _store.writeString(progressKey(textbookId), '$page');
    } on Object catch (error, stackTrace) {
      _logger.w('保存阅读进度失败', error, stackTrace);
    }
    notifyListeners();
  }

  // ==================== 组织 ====================

  /// 置顶 / 取消置顶。
  Future<void> togglePin(Set<String> textbookIds) async {
    if (textbookIds.isEmpty) {
      return;
    }
    final Set<String> pinned = <String>{..._arrangement.pinnedIds};
    // 全部已置顶时这一下是"取消置顶"，否则一并置顶——与复选框语义一致，
    // 用户不必去想"混合状态该怎样"。
    final bool allPinned = textbookIds.every(pinned.contains);
    if (allPinned) {
      pinned.removeAll(textbookIds);
    } else {
      pinned.addAll(textbookIds);
    }
    await _saveArrangement(_arrangement.copyWith(pinnedIds: pinned));
  }

  /// 把若干本归到一个分组；[group] 传 `null` 或空白表示移出分组。
  Future<void> assignGroup(Set<String> textbookIds, String? group) async {
    if (textbookIds.isEmpty) {
      return;
    }
    final String name = group?.trim() ?? '';
    final Map<String, String> next = <String, String>{..._arrangement.groupOf};
    for (final String id in textbookIds) {
      if (name.isEmpty) {
        next.remove(id);
      } else {
        next[id] = name;
      }
    }
    await _saveArrangement(
      _arrangement.withGroups(next, created: name.isEmpty ? null : name),
    );
  }

  /// 批量移出书架（删除本地文件）。
  ///
  /// 阅读进度、置顶、分组一并清理——留着这些记录只会让"删过的书"
  /// 在下次下载时带着旧进度复活。
  Future<void> removeMany(Set<String> textbookIds) async {
    if (textbookIds.isEmpty) {
      return;
    }
    for (final String id in textbookIds) {
      try {
        final File file = File(
          '${_paths.pdfDirectory.path}${Platform.pathSeparator}$id.pdf',
        );
        if (file.existsSync()) {
          await file.delete();
        }
        await _store.delete(progressKey(id));
        _progress.remove(id);
      } on Object catch (error, stackTrace) {
        _logger.w('移出书架失败：$id', error, stackTrace);
      }
    }
    final Map<String, String> groups = <String, String>{..._arrangement.groupOf}
      ..removeWhere((String id, String _) => textbookIds.contains(id));
    final LibraryArrangement next = _arrangement.withGroups(groups);
    await _saveArrangement(
      next.copyWith(
        pinnedIds: <String>{...next.pinnedIds}..removeAll(textbookIds),
      ),
    );
  }

  /// 移出一本。
  Future<void> remove(String textbookId) => removeMany(<String>{textbookId});

  // ==================== 内部实现 ====================

  String _idOf(File file) =>
      file.uri.pathSegments.last.replaceAll(RegExp(r'\.pdf$'), '');

  Future<void> _saveArrangement(LibraryArrangement next) async {
    _arrangement = next;
    try {
      await _store.writeString(
        StorageKeys.libraryArrangement,
        jsonEncode(next.toJson()),
      );
    } on Object catch (error, stackTrace) {
      _logger.w('保存书架整理信息失败', error, stackTrace);
    }
    await refresh();
  }

  Future<void> _loadArrangement() async {
    try {
      final String? raw = await _store.readString(
        StorageKeys.libraryArrangement,
      );
      if (raw == null || raw.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _arrangement = LibraryArrangement.fromJson(decoded);
      }
    } on Object catch (error, stackTrace) {
      _logger.w('读取书架整理信息失败', error, stackTrace);
    }
  }

  Future<void> _loadProgress() async {
    try {
      final Set<String> keys = await _store.keys();
      for (final String key in keys) {
        if (!key.startsWith(StorageKeys.readingProgress)) {
          continue;
        }
        final String? raw = await _store.readString(key);
        final int? page = raw == null ? null : int.tryParse(raw);
        if (page != null) {
          _progress[key.substring(StorageKeys.readingProgress.length)] = page;
        }
      }
    } on Object catch (error, stackTrace) {
      _logger.w('读取阅读进度失败', error, stackTrace);
    }
  }
}
