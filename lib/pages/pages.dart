/// 页面层。
///
/// 目录约定：一个页面一个目录，主文件与目录同名，
/// 页面私有的子组件与状态类放在同一目录下：
/// ```
/// pages/
/// ├── pages.dart          # 本文件，统一出口
/// ├── app_navigator.dart  # 路由表组装（与页面强绑定，因此放在这一层）
/// ├── shell/              # 四 Tab 外壳
/// ├── library/            # 书架
/// ├── browse/             # 目录树
/// ├── downloads/          # 下载队列
/// └── settings/           # 设置
/// ```
library;

export 'app_navigator.dart';
export 'browse/browse.dart';
export 'catalog/catalog_setup_page.dart';
export 'downloads/downloads.dart';
export 'error/not_found_page.dart';
export 'library/library.dart';
export 'login/login_page.dart';
export 'reader/reader_page.dart';
export 'settings/settings.dart';
export 'shell/home_shell.dart';
export 'textbook/textbook_detail_page.dart';
