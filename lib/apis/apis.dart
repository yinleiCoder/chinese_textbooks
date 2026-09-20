/// 接口层。
///
/// 职责是"有哪些接口、每个接口返回什么类型"，**不负责**怎么发请求——
/// 传输细节（拦截器、重试、缓存、超时、签名）全部封装在 `services/http/`。
///
/// ```
/// apis/
/// ├── apis.dart            # 本文件，统一出口
/// ├── api_client.dart      # 通用客户端：把 Dio 收敛成 Result
/// ├── api_response.dart    # 服务端响应信封
/// ├── nd_endpoints.dart    # 平台接口地址（接口变了只改这里）
/// └── catalog_api.dart     # 教材目录（版本探针 / 分片 / 标签树）
/// ```
library;

export 'api_client.dart';
export 'api_response.dart';
export 'catalog_api.dart';
export 'nd_endpoints.dart';
export 'textbook_api.dart';
