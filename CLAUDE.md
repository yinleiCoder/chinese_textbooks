# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

国家中小学智慧教育平台（basic.smartedu.cn）的第三方客户端，Flutter 单代码库跑 Windows + Android。
**没有自己的后端**——所有数据来自平台接口，因此接口契约、签名、限流参数是项目里最容易过期的部分，
全部收敛在 `lib/values/nd_config.dart`。README 的「平台接口」一节记了几个实测得来、容易踩错的事实
（`ti_items` 是空数组、标签树是 DAG 不是树、私有 CDN 的 HEAD 返回 200 但 GET 返回 401 等），改接口相关代码前先读它。

## 常用命令

```bash
flutter pub get
dart run build_runner build        # 生成 *.g.dart —— 这些文件**没有入库**，克隆后必跑
flutter analyze                    # 必须保持零问题
flutter test                       # 全量
flutter test test/pages/library_sections_test.dart            # 单个文件
flutter test test/pages/library_sections_test.dart --plain-name "分组之间按创建顺序"   # 单个用例

flutter run -d windows             # 桌面端
dart run tool/setup_pdfium.dart    # 首次构建前、以及每次 flutter clean 之后都要跑
```

格式化只格式化**自己改动的文件**（`dart format lib/pages/library/library.dart`）。
不要整目录跑：当前 Dart 格式化器与仓库里若干既有文件不一致，整目录跑会带出一大片无关 diff。

## 构建前的前置条件

这三件事任一缺失都会让构建以看着毫不相干的错误失败：

1. **`dart run tool/setup_pdfium.dart`** —— `pdfrx` 通过构建钩子在构建时从 GitHub Release 下
   PDFium。该下载走 `release-assets.githubusercontent.com`，网络不稳时会被代理包装成
   **HTTP 404**（具有误导性，上游版本一直存在）。脚本把二进制预置好，钩子就不会再发那次请求。
2. **`windows/tools/nuget.exe`** —— `flutter_inappwebview_windows` 构建时要用它拉三个 NuGet 包。
   它是 9MB 二进制、**被 .gitignore 排除**，新克隆的仓库里没有。缺失时 CMake 会打印获取命令。
3. **`*.g.dart`** —— `lib/apis/api_response.g.dart`、`lib/entity/textbook.g.dart` 等由
   `json_serializable` 生成且未入库，没有它们 `flutter analyze` 会因为找不到 part 文件直接失败。

## 分层架构

依赖方向**单向**，README 的「目录结构」一节有完整说明。几条真正会影响改动方式的规则：

- **`services/app_dependencies.dart` 是唯一的组合根**，全项目只有它允许同时 import 所有层。
  其余代码一律通过构造函数接收依赖。新增服务时在这里装配，不要在别处 new 或搞单例。
- **每个目录都有同名 barrel**（`values/values.dart`、`services/cache/cache.dart`…），
  外部统一从 barrel 导入，内部文件增删不影响调用方。
- **不使用 MVVM**。页面直接消费 `Provider`，没有 ViewModel 层。页面私有状态放
  `pages/<功能>/<功能>_provider.dart`，只有跨页面共享的才进 `providers/`。
- **路由表在 `pages/app_navigator.dart` 而不是 `services/router/`**：它必须 import 每一个页面，
  放服务层会形成 `services → pages` 的反向依赖。`services/router/` 只留路径常量与导航观察者。
- **`AuthSessionProvider` 必须只有一个实例**（由组合根创建）。网络层拿它算签名、下载器拿它决定走公开
  镜像还是私有域——曾经两处各建一个，结果是网络层永远看不到登录凭据，所有签名请求 401。

## 几处约定

- **注释一律中文，且解释「为什么」**。这个仓库的注释密度是有意为之：凡是反直觉的取值、
  绕开的平台坑、删掉又加回来的分支，都要在注释里留下原因。改动时保持同样的密度。
- **不写裸数字**，尺寸与字号全取 `values/app_dimens.dart`（`AppDimens.gapMd` 而非 `16`）。
  设计稿尺寸在 `AppConfig.designSize`，是 `.w/.h/.r/.sp` 的换算基准。桌面端不缩放（见 `AppConfig.scaleUi`）。
- **不抛异常，用 `Result<T>`**。`AppFailure` 是 `sealed` 的，`switch` 有穷尽检查；新增失败类型时
  所有未处理分支会在编译期报错。
- **缓存默认关闭**（`CachePolicy.none`），要缓存必须显式声明——避免"某个接口被悄悄缓存了"。
  目录数据是例外：它走 `CatalogFileStore` 独立文件存储，**不进 KV 缓存**（shared_preferences 在
  Android 上是全量读进内存的 XML，塞几十 MB 进去会让每次读写都付出代价）。

## 容易造成实质损害的坑

**Windows 的 `ProductName` 就是数据目录。** `path_provider` 在 Windows 上用 exe 版本信息里的
`CompanyName` + `ProductName` 拼出 `%APPDATA%\<公司名>\<产品名>`。改
[windows/runner/Runner.rc](windows/runner/Runner.rc) 里的 ProductName 等于换数据目录，
老用户升级后已下载的教材、阅读进度、登录态会集体"失踪"（文件还在旧目录里）。这个坑踩过一次。

**展示名有四份拷贝**，改名要一起改：`AppConfig.appName`、AndroidManifest 的 `android:label`、
`windows/runner/main.cpp` 的窗口标题、`Runner.rc` 的 `ProductName`/`FileDescription`。

**目录索引的标签兜底查找已被刻意删除**（`catalog_index.dart` 的 `_findChild`）。平台给整库的
「上册」用同一个 tag_id，而它在标签树里只挂在某一个分支下；一旦允许"本层找不到就退回全局查找"，
各学科的「上册」会被全搬进那个分支。新增任何"找不到就全局找"的兜底前，先读那段注释。

**混淆符号表不能公开**。`--split-debug-info` 产出的 `app.*.symbols` 能反解混淆，
发布流水线只把它作为 Actions artifact 上传，**不进 Release**。

## 测试

`test/` 下按 `lib/` 的层级对应摆放，夹具在 `test/services/catalog_fixture.dart`（手工构造的小目录树，
不要换成线上数据——3565 条的真实数据一旦断言失败根本看不出是哪层错了）。

**`testWidgets` 里不要调用 `assignGroup` / `togglePin` 这类会重扫磁盘的方法**：
它们落盘后会 `refresh()` 重扫 `dart:io`，而 `testWidgets` 跑在 FakeAsync 里，真实异步永远不会完成，
测试会直接挂住（不是失败，是挂住）。要在 widget 测试里准备这些状态，就在 `setUp`（FakeAsync 之外）
里做好再 pump。纯粹的分区逻辑测试放 `library_sections_test.dart`，它不建 widget 树。

## 发版

打 tag 即发：`git tag v1.0.0 && git push origin main --tags`。

**版本号来自 tag，不是 `pubspec.yaml`**；Android 的 versionCode 取 `github.run_number`，
两者都通过 `--build-name` / `--build-number` 显式传给构建。`--build-number` 不能省——
不传的话 versionCode 永远停在 pubspec 的 `+1`，而系统只允许更大的 versionCode 覆盖安装，
用户更新时会装到一半报「应用未安装」。也别把 Android 构建拆到第二个 workflow 文件里：
`run_number` 是每个 workflow 各自计数的，两个文件会让 versionCode 倒退。

Windows 只出一个 Inno Setup 安装包（整个 Release 目录都被封进去），打包前会补 MSVC 运行库——
Flutter 自己不打包 C 运行时，缺了它目标机器双击 exe 毫无反应。README 的「发版」一节有
secrets 清单与本地出包命令。
