/// 网络传输层基础设施。
///
/// 这一层负责"怎么把请求发出去"，不负责"有哪些接口"——后者属于 `apis/`。
library;

export 'dio_factory.dart';
export 'failure_mapper.dart';
export 'http_config.dart';
export 'interceptor/interceptor.dart';
export 'nd_auth_signer.dart';
export 'nd_credential_provider.dart';
