import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/utils/validators.dart';

/// 入站端口偏好。
///
/// HTTP 客户端（core/http_client 需要 mixedPort 建立本地代理连接）与
/// sing-box 配置（ConfigOptions）都要读写它，属基础设施偏好，
/// 故从 features/settings/data/config_option_repository.dart 下沉到这里。
abstract class PortPreferences {
  static final mixedPort = PreferencesNotifier.create<int, int>(
    "mixed-port",
    12334,
    validator: (value) => isPort(value.toString()),
  );
}
