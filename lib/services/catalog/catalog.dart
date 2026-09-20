/// 教材目录层。
///
/// 职责是把平台上的教材清单变成"可以查询、可以勾选"的内存结构，
/// 并负责它在磁盘上的缓存与增量更新。
///
/// 数据流：
/// ```
/// 平台分片(4×10MB) ──parseCatalogPart(isolate)──▶ 列式分片文件(~250KB/片)
///                                                      │
///                          CatalogShardCodec.decode   │
///                                                      ▼
///            标签树 ──▶ CatalogIndex.build ◀── 行数据
///                            │
///                            ├─▶ 分类树（CatalogNode）
///                            ├─▶ 各层维度（CatalogLevel）
///                            └─▶ 筛选与搜索
///
///            CatalogSelection 在此之上维护三态勾选
/// ```
///
/// 更新判定用**分片 ETag**，不用平台给的 `module_version`——后者实测与内容
/// 变更无关（停在 2023，内容更新到 2026），拿它判断会导致用户永远看不到新教材。
library;

export 'catalog_downloader.dart';
export 'catalog_file_store.dart';
export 'catalog_filter.dart';
export 'catalog_index.dart';
export 'catalog_manifest.dart';
export 'catalog_progress.dart';
export 'catalog_repository.dart';
export 'catalog_selection.dart';
export 'catalog_snapshot_codec.dart';
