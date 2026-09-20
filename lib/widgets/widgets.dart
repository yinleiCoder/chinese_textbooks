/// 通用组件层。
///
/// 判定标准：**被两个以上页面用到，且不含业务语义**。
/// 只服务单个页面的组件放在 `pages/<功能>/` 下，避免这里堆积一次性代码。
///
/// 所有组件都必须：
/// - 尺寸取自 `AppDimens`，不出现魔法数字；
/// - 颜色取自 `Theme.of(context)`，自动适配深色模式；
/// - 文案支持外部传入，默认值取自 `AppStrings`。
library;

export 'app_empty_view.dart';
export 'app_error_view.dart';
export 'app_filter_bar.dart';
export 'app_loading_view.dart';
export 'app_network_image.dart';
export 'app_search_field.dart';
export 'app_tri_state_tile.dart';
