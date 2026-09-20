import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../values/values.dart';
import 'app_loading_view.dart';

/// 统一的网络图片组件。
///
/// 在 `cached_network_image` 之上补齐三件业务侧总要做的事：
/// 1. **占位与错误兜底**——不留白块，也不让加载失败看起来像布局错乱；
/// 2. **屏幕适配**——宽高按设计稿等比换算，不写死 dp；
/// 3. **渐显过渡**——避免图片"啪"地跳出来打断阅读。
///
/// 缓存由 `cached_network_image` 自行管理（内存 + 磁盘两级），
/// 与 `services/cache/` 的接口缓存互不干扰，也不需要复用。
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    required this.url,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.image_outlined,
  });

  /// 图片地址。
  final String url;

  /// 宽度，为空时由父级约束决定。
  final double? width;

  /// 高度，为空时由父级约束决定。
  final double? height;

  /// 填充方式。
  final BoxFit fit;

  /// 圆角。
  final BorderRadius? borderRadius;

  /// 加载失败时展示的图标。
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final BorderRadius? borderRadius = this.borderRadius;
    final Widget image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (BuildContext context, String url) =>
          _placeholder(context, showIndicator: true),
      errorWidget: (BuildContext context, String url, Object error) =>
          _placeholder(context, showIndicator: false),
    );

    if (borderRadius == null) {
      return image;
    }
    return ClipRRect(borderRadius: borderRadius, child: image);
  }

  Widget _placeholder(BuildContext context, {required bool showIndicator}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        width: width,
        height: height,
        child: showIndicator
            ? const AppLoadingView(compact: true)
            : Center(
                child: Icon(
                  placeholderIcon,
                  size: AppDimens.iconLg,
                  color: scheme.outline,
                ),
              ),
      ),
    );
  }
}
