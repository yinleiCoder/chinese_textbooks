# 无界课本

国家中小学智慧教育平台（basic.smartedu.cn）的第三方客户端，Windows + Android 双端。
支持浏览、搜索、筛选、批量下载与离线阅读平台上的电子教材。

> 仓库名与 Dart 包名仍是 `chinese_textbooks`（包名只能用小写 ASCII 标识符），
> 软件的展示名与发布名统一为「无界课本」。

> 本应用与国家中小学智慧教育平台没有隶属或合作关系。教材版权归原平台及相关权利人所有，
> 仅供个人学习与教学参考，请勿用于商业用途或二次分发。

## 功能

| 模块 | 能力 |
| --- | --- |
| 目录 | 2911 本教材的分类树（学段 → 学科 → 版本 → 年级 → 册次），按维度筛选、关键词搜索 |
| 选择 | 树级三态复选框，可整类勾选；勾选与筛选解耦，可跨条件分次勾选后一起下载 |
| 详情 | 页数、体积、出版社、分类路径；没有源文件的条目明确提示"暂不提供在线阅读" |
| 登录 | 内嵌平台官方登录页，用**用户自己的账号**登录；凭据只进系统安全存储 |
| 下载 | 并发 3 + 间隔 200ms 限流，镜像轮换，断流退避，`.part` 原子落盘，失败可单独重试 |
| 阅读 | 内置 PDF 阅读器，记录并恢复阅读进度 |
| 书架 | 只展示已下载到本地的教材，可导出到任意位置 |
| 离线 | 目录数据增量缓存，已下载的教材完全离线可读 |

## 技术选型

选型原则是优先使用 pub.dev 上下载量与点赞数最高、且仍在积极维护的库。

| 领域 | 选型 | 说明 |
| --- | --- | --- |
| 路由 | [go_router](https://pub.dev/packages/go_router) | Flutter 官方维护的声明式路由 |
| 状态管理 | [provider](https://pub.dev/packages/provider) | `ChangeNotifier` + `InheritedWidget`，无额外框架抽象 |
| 网络 | [dio](https://pub.dev/packages/dio) | 拦截器与适配器体系完整 |
| 屏幕适配 | [flutter_screenutil](https://pub.dev/packages/flutter_screenutil) | 按设计稿等比换算宽高、圆角与字号 |
| 本地存储 | [shared_preferences](https://pub.dev/packages/shared_preferences) | 缓存持久层与普通设置 |
| 安全存储 | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | 令牌等敏感数据 |
| 图片缓存 | [cached_network_image](https://pub.dev/packages/cached_network_image) | 内存 + 磁盘两级图片缓存 |
| 连通性 | [connectivity_plus](https://pub.dev/packages/connectivity_plus) | 驱动离线态展示 |
| 日志 | [logger](https://pub.dev/packages/logger) | 替代 `print`，按环境分级 |
| 日期 | [intl](https://pub.dev/packages/intl) | 日期与时长的本地化格式化 |
| 值语义 | [equatable](https://pub.dev/packages/equatable) | 实体与策略对象的相等性判断 |
| 代码生成 | [json_serializable](https://pub.dev/packages/json_serializable) | JSON 序列化 |

## 平台接口

平台接口随时可能变（参考项目的历史 issue 显示平均每年要跟进几次）。
**所有域名、路径、请求头、限流参数都收敛在 [lib/values/nd_config.dart](lib/values/nd_config.dart)**，
接口变动时只需要改这一个文件。

几个实测得来、容易踩错的事实：

- **清单里的 `ti_items` 是空数组**，文件地址必须逐本请求详情才能拿到；
- **`module_version` 与内容更新无关**（实测停在 2023 而内容更新到 2026），
  缓存失效一律用分片 ETag；
- **标签树是 DAG 不是树**（185 个 tag_id 里 101 个重复出现），节点身份必须用路径；
- **标签树的分层是 `分组 → 节点 → 分组 → 节点` 交替的**，把分组当节点读会静默挂不上任何书；
- **私有 CDN 的 HEAD 返回 200 但 GET 返回 401**，任何探测都必须用 GET；
- **私有域必须带 `X-ND-AUTH` 签名**，且签名按 URL 现算、不能跨 URL 复用。

## 目录结构

```
lib/
├── apis/            接口层：有哪些接口、返回什么类型
├── entity/          实体层：纯数据模型，不依赖 Flutter
├── pages/           页面层：一个页面一个目录
├── providers/       状态层：跨页面共享的状态
├── services/        服务层：日志、存储、缓存、网络、路由、连通性
├── utils/           工具层：Result / Failure / 扩展方法
├── values/          常量层：配置、颜色、尺寸、文案、主题、存储键
├── widgets/         组件层：无业务语义的通用组件
└── main.dart        入口：创建依赖容器并注入 widget 树
```

**依赖方向是单向的**，不允许出现反向 import：

```
apis/ ──▶ services/ ──▶ utils/ ──▶ values/
providers/ ──▶ apis/ + services/
pages/ + widgets/ ──▶ providers/ + values/
```

唯一的例外是 `services/app_dependencies.dart`。它是**组合根（Composition Root）**，
必须认识所有层才能把它们装配起来。整个应用只有这一个文件可以"什么都 import"。

### 分层约定

- **不使用 MVVM**。页面直接消费 `Provider`，不引入 ViewModel 层。
- 页面私有状态放在 `pages/<功能>/<功能>_provider.dart`，
  只有跨页面共享的状态才放进 `providers/`。
- 每个目录都有同名 barrel 文件（如 `values/values.dart`），
  外部统一从 barrel 导入，内部文件调整不影响调用方。

## 缓存设计

缓存是本骨架中投入最多设计的部分，位于 `services/cache/`。整体由四个可独立替换的
角色拼装而成：

```
CacheManager          门面：按业务语义读写，屏蔽全部细节
  ├── CachePolicy           决策：读谁、写谁、存多久
  ├── CacheCodec            编解码：值 ↔ 字符串
  └── CacheStore            存储契约
        ├── MemoryCacheStore        一级：进程内 LRU
        ├── PreferencesCacheStore   二级：落盘持久化
        └── TieredCacheStore        组合：多级串联 + 回填
```

### 五种缓存策略

| 策略 | 行为 | 适用场景 |
| --- | --- | --- |
| `networkOnly` | 不读不写缓存 | 登录、支付 |
| `cacheOnly` | 只读缓存，未命中即失败 | 已下载的课程内容 |
| `cacheFirst` | 缓存新鲜就用缓存 | 低频变更的教材目录 |
| `networkFirst` | 先网络，失败回落缓存 | 需要时效但也要能离线看 |
| `staleWhileRevalidate` | 立即返回旧数据 + 后台刷新 | 首页、信息流 |

### 关键设计决策

- **缓存失败永不打断业务**。`CacheStore` 的实现内部消化异常并降级，
  缓存坏掉最多让应用变慢，不会让功能不可用。
- **`read` 返回过期条目**。新鲜度判断交给 `CacheManager`，
  因为离线兜底和 `staleWhileRevalidate` 恰恰需要读到过期数据。
- **持久化缓存按 LRU 淘汰**，并有独立的保留期清理，不会无限增长。
- **写操作不参与缓存**。只有 `GET` 会被缓存，
  `POST` 的重复提交问题应当用幂等键解决，而不是缓存。
- **ETag / Last-Modified 条件请求**：命中 `304` 时复用本地数据，
  只延长有效期，省掉一次响应体传输。
- **缓存键携带身份标识**，避免切换账号后读到上一位用户的数据。

### 给接口配置缓存策略

优先级：请求级显式指定 > 路径规则注册表 > 默认不缓存。

```dart
// 方式一：单个请求显式指定
dio.get(
  '/textbooks',
  options: Options(extra: <String, dynamic>{
    CacheRequestKeys.policy: CachePolicy.longLived,
  }),
);

// 方式二：在 CachePolicyRegistry 上按路径注册（推荐，集中声明）
registry
  ..registerPrefix('/api/v1/textbooks/', CachePolicy.longLived)
  ..registerPrefix('/api/v1/textbooks', CachePolicy.standard);
```

默认策略刻意设为 `CachePolicy.none`：新增接口默认不缓存，
需要缓存必须显式声明，避免"某个接口悄悄被缓存了"这类意外。

## 错误处理

请求结果统一用 `Result<T>` 表达，不抛异常：

```dart
final Result<List<Textbook>> result = await api.get(
  '/textbooks',
  decoder: ApiClient.envelope<List<Textbook>>(Textbook.listFromJson),
);

switch (result) {
  case Success(:final data):
    render(data);
  case Failure(:final failure):
    showError(failure.message);
}
```

`AppFailure` 是 `sealed` 的，`switch` 会做穷尽检查——新增失败类型时，
所有未处理的分支会在编译期报错。UI 层可以直接用
`AppErrorView.fromFailure(failure, onRetry: ...)`，
它会按 `isRetryable` 自动决定要不要给重试按钮（4xx 与解析失败不给，
因为重试多少次结果都一样）。

## 屏幕适配

设计稿尺寸在 `values/app_config.dart` 的 `AppConfig.designSize` 中声明（当前 `360 × 690`），
必须与 UI 稿一致，它是所有换算的基准。

业务代码中**不写裸数字**，统一取自 `values/app_dimens.dart`：

```dart
// 不推荐
SizedBox(height: 16)

// 推荐
SizedBox(height: AppDimens.gapMd)
```

`AppDimens` 内部已经按语义选好了换算方式：
`.w` 用于宽度与水平间距，`.h` 用于需要"一屏高度固定"的场景，
`.r` 用于圆角与正方形边长，`.sp` 用于字号。需要临时换算时可直接用扩展方法
（`16.w` / `16.r` / `16.sp`）。

## 常用命令

```bash
flutter pub get                  # 安装依赖

# 代码生成（修改了带 @JsonSerializable 的类之后必须执行）
dart run build_runner build
dart run build_runner watch      # 开发期监听变更

flutter analyze                  # 静态分析，应当保持零问题
flutter test                     # 单元测试与组件测试
dart format lib test             # 格式化

# 切换环境运行
flutter run --dart-define=APP_ENV=staging
```

## 应用图标与名称

**图标**的设计源是 `assets/兔子.svg`，而两个平台都只认位图，中间隔了一层派生：

```bash
dart run tool/generate_app_icons.dart   # SVG → 母图 PNG + Windows 多尺寸 .ico
dart run flutter_launcher_icons         # 母图 → Android 各密度 mipmap
```

改图标只改 SVG，然后依次跑上面两条命令。派生结果都进版本库，日常构建不需要跑这条链。
细节（为什么 Windows 不走 flutter_launcher_icons、为什么只让浏览器画一张图）
写在 [tool/generate_app_icons.dart](tool/generate_app_icons.dart) 顶部。

**名称**「无界课本」在四处各有一份拷贝，改名字时四处要一起改：

| 位置 | 作用 |
| --- | --- |
| [lib/values/app_config.dart](lib/values/app_config.dart) 的 `AppConfig.appName` | 应用内展示（`MaterialApp.title`） |
| [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) 的 `android:label` | Android 桌面图标名 |
| [windows/runner/main.cpp](windows/runner/main.cpp) 的窗口标题 | Windows 窗口标题 |
| [windows/runner/Runner.rc](windows/runner/Runner.rc) 的 `ProductName` / `FileDescription` | 文件属性、任务管理器 |

Dart 包名（`pubspec.yaml` 的 `name`）只能用小写 ASCII 标识符，因此仍是 `chinese_textbooks`。

> ⚠ **改 Windows 的 `ProductName` 等于改数据目录。** `path_provider` 是用 exe 版本信息里的
> `CompanyName` + `ProductName` 拼出 `%APPDATA%\<公司名>\<产品名>` 的，改名之后应用会在
> 新目录里从零开始：已下载的教材、阅读进度、登录态全部"失踪"（文件其实还在旧目录）。
> 本项目的产品名从 `chinese_textbooks` 改成「无界课本」时就踩过一次，数据靠手工搬迁找回。
> 要再改名，先规划好旧目录怎么搬。

## 发版

推一个 `v*` 标签即可，[.github/workflows/release.yml](.github/workflows/release.yml)
会把两端都构建出来并挂到 GitHub Release 上：

```bash
git tag v1.2.0 && git push origin main --tags
```

**版本号只有一个来源：标签。** 版本名取标签去掉 `v`，Android 的 `versionCode`
取 `github.run_number`（保证单调递增）。这两项都通过 `--build-name` /
`--build-number` 显式传给构建，不读 `pubspec.yaml` ——
`pubspec.yaml` 里的 `version` 只是本地开发用的默认值。

> `--build-number` **不能省**：不传的话 versionCode 永远停在 pubspec 的 `+1`，
> 而系统只允许 versionCode 更大的包覆盖安装，用户更新时会装到一半报「应用未安装」。

流水线四个 job：`check`（analyze + test）→ `build-windows` / `build-android` → `release`。
两个构建都依赖 `check`，红了就不往下走。在 Actions 页面手动触发只跑构建、不发 Release，
用来验证流水线本身。

### 产物

资产名**不带版本号**，所以下面这两个链接永远指向最新版：

| 文件 | 说明 |
| --- | --- |
| `wujie-textbook-windows-x64-setup.exe` | Windows 安装包（Inno Setup），双击即装 |
| `wujie-textbook-android.apk` | Android 安装包，首次需允许「安装未知来源应用」 |

```
https://github.com/yinleiCoder/chinese_textbooks/releases/latest/download/wujie-textbook-windows-x64-setup.exe
https://github.com/yinleiCoder/chinese_textbooks/releases/latest/download/wujie-textbook-android.apk
```

Windows 只出这一个 exe：整个 Release 目录（exe + 各插件 dll + `data\`）都被
Inno Setup 封了进去，所以用户不需要知道"不能只拷 exe"这回事。

打包前会**补进 MSVC 运行库**（`msvcp140.dll` 等约 10 个 dll）。Flutter 自己不打包
C 运行时，目标机器没装过 Visual Studio 的话，双击 exe 会毫无反应——连错误框都不弹。
这一步不能省。

### 混淆与符号表

两端都用 `--obfuscate --split-debug-info` 构建，并额外存一份 `obfuscation-map.json`。
符号表能让混淆失效，所以**只作为 Actions artifact 上传（90 天），不进 Release**。
排查线上崩溃时从 workflow 运行页下载，然后：

```bash
flutter symbolize -i <崩溃日志> -d <解压出来的 app.android-arm64.symbols>
```

混淆不是加密：它只改符号名，**不会**保护资源、也挡不住逆向。真正的密钥
（平台令牌等）本来就只放系统安全存储，不进代码。

### 需要的仓库 Secrets

`Settings → Secrets and variables → Actions`：

| Secret | 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 的 base64，见下 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 口令 |
| `ANDROID_KEY_ALIAS` | 别名，通常 `upload` |
| `ANDROID_KEY_PASSWORD` | key 口令（通常同上） |

没配 `ANDROID_KEYSTORE_BASE64` 时流水线**不会失败**，只会打一条 warning 并改用
debug 签名。但 debug 签名的包**换台机器就发不出可覆盖安装的更新**（Android 要求
同包名同签名），只适合内测——正式发布务必先配好。

keystore 的生成方式见 [android/key.properties.example](android/key.properties.example)。
**请离线备份 keystore**：丢了这个文件，就再也无法给已上架的应用发新版。

Windows 安装包目前**没有代码签名**。用户安装时 Windows 会弹 SmartScreen 警告
（"未知发布者"）。要消掉它得买一张代码签名证书，再用 `signtool` 签——这是笔
持续支出，本项目暂时没做。

## 静态分析

`analysis_options.yaml` 在 `flutter_lints` 之上开启了更严格的一组规则，
并启用了三项严格模式：

- `strict-casts`：禁止隐式向下转型
- `strict-inference`：推断不出类型时报错，避免 `dynamic` 扩散
- `strict-raw-types`：裸泛型视为错误

几条值得注意的规则：

- `unawaited_futures`：忘记 `await` 的 Future 必须显式写 `unawaited(...)`
- `cancel_subscriptions` / `close_sinks`：资源忘记释放会直接报错
- `comment_references`：文档注释里写错的 `[类名]` 会被发现
- `require_trailing_commas` / `directives_ordering`：格式统一，减少 diff 噪音

规则一旦开启就应当保持绿灯。确需例外时用 `// ignore: 规则名` 就地豁免并写明原因，
不要关掉整条规则。

## 构建前置准备

`flutter pub get` 之后、首次构建之前，需要执行一次：

```bash
dart run tool/setup_pdfium.dart
```

它把 `pdfrx` 依赖的 PDFium 二进制预置到构建钩子期望的位置（Windows x64 与 Android 三个 ABI）。
原因见下方「PDFium 下载受网络影响」。脚本幂等，**每次 `flutter clean` 之后需要重跑**
（clean 会删除 `.dart_tool`）。只想补某个平台时可传架构参数，如 `dart run tool/setup_pdfium.dart arm64`。

Windows 端还需要 NuGet CLI。`windows/CMakeLists.txt` 会优先在 `windows/tools/` 里找，
找不到时给出获取命令：

```bash
curl -L -o windows/tools/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe
```

## 已知环境问题

以下问题都已在仓库中修复，此处记录原因，避免后来者再次踩坑。

### Windows 构建：C4819 编码错误

Flutter 的 Windows 模板对所有目标（含插件）启用了 `/WX`（警告视为错误）。
MSVC 默认按系统本地代码页读取源文件，在中文 Windows（代码页 936）下，
插件源码中的 UTF-8 字符会触发 C4819 并直接导致构建失败。

修复：在 `windows/CMakeLists.txt` 的 `APPLY_STANDARD_SETTINGS` 中加上 `/utf-8`。

### Android 构建：Kotlin 增量缓存报错

在 Windows 上编译含 Kotlin 源码的插件时，会随机出现
`Could not close incremental caches` / `Storage ... is already registered`
导致构建失败，清理 `build/` 与重启 Gradle 守护进程都无法稳定修复。

修复：在 `android/gradle.properties` 中设置 `kotlin.incremental=false`。
代价是插件模块的 Kotlin 编译不再增量，对构建耗时影响很小。

### Windows 构建：插件需要 NuGet

`flutter_inappwebview_windows` 在构建时用 NuGet 拉取 WebView2、WIL、nlohmann.json 三个包。
系统没装 NuGet 时，报错是一串难以理解的 `MSB3073 / NUGET-NOTFOUND`（退出码 9009）。

修复：把 `nuget.exe` 放进 `windows/tools/`，并在 `windows/CMakeLists.txt` 中把它加进
`CMAKE_PROGRAM_PATH`——这样不需要改动开发者的系统 PATH。缺失时 CMake 会给出明确的获取命令。

### Windows 构建：`<experimental/coroutine>` 被 MSVC 判为错误

`flutter_inappwebview_windows` 使用了 `<experimental/coroutine>` 与 `/await`。
MSVC 14.51（VS 2026 / v180 工具集）已将其从弃用警告升级为硬错误 C2338。

修复：在 `windows/CMakeLists.txt` 中定义
`_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`（这是微软提供的过渡开关）。
待该插件迁移到 C++20 `<coroutine>` 后即可删除。

### PDFium 下载受网络影响（构建失败时先看这条）

`pdfrx` 通过 `pdfium_dart` 的构建钩子在**构建时**从 GitHub Release 下载 PDFium（4~7MB）。
该下载走 `release-assets.githubusercontent.com`，在部分网络环境下会间歇性失败，
报错形如 `Failed to download PDFium: HTTP 404 ...chromium%2F7811/pdfium-win-x64.tgz`。

> **注意**：这个 404 具有误导性。经核实 `chromium/7811` 这个 Release 与它的
> `pdfium-win-x64.tgz` 资产**一直存在**，是网络链路（代理/加速器）把失败包装成了 404，
> 并非上游删了版本。遇到时不要急着降级 pdfrx，先确认网络。

修复：`dart run tool/setup_pdfium.dart` 预置二进制。钩子内部有
`if (await output.exists()) return;`，文件已存在就不会再发起那次网络请求。
