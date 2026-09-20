import '../../apis/apis.dart';
import '../../entity/entity.dart';

/// 决定一次下载按什么顺序尝试哪些地址。
///
/// ## 为什么按登录态分叉
///
/// 实测：私有域（`-private`）不带凭据一律 401，约覆盖 100% 的教材；
/// 去掉 `-private` 的公开镜像不需要任何凭据，但**只覆盖约 30%**
/// （随机抽样 10 本命中 3 本）。
///
/// 因此：
/// - **已登录** → 直接走私有域。私有域是可靠路径，先试公开域纯属浪费一次
///   请求——而且那一次大概率是 403，白占一个限流配额。
/// - **未登录** → 先试公开镜像碰运气，全失败才告诉用户需要登录。
final class MirrorPlanner {
  const MirrorPlanner();

  /// 为一次下载产出候选地址序列，顺序即尝试顺序。
  List<Uri> plan(DownloadTask task, {required bool loggedIn}) {
    if (task.mirrors.isEmpty) {
      return const <Uri>[];
    }

    if (loggedIn || task.requiresAuth) {
      // `requiresAuth` 表示上次已经确认过这本需要签名，同样不必再撞公开域。
      return NdEndpoints.privateMirrors(task.mirrors.first);
    }

    return <Uri>[
      ...NdEndpoints.publicMirrors(task.mirrors.first),
      ...NdEndpoints.privateMirrors(task.mirrors.first),
    ];
  }

  /// 该地址是否属于需要签名的私有域。
  static bool isPrivate(Uri url) => NdEndpoints.privateMirrors(url).length > 1;
}
