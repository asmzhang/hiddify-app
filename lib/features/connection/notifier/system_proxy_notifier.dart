import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 这个文件放「内核」和「接管」**两个独立的量**。
///
/// 原来是"内核常驻模式"的实现（用一个选项 + 运行时开关去模拟），已按 nekoray 的模型重构：
/// nekoray 的 `neko_start` 只把配置装进内核，**接管流量靠 `spmode_system_proxy` /
/// `spmode_vpn` 两个独立开关** —— 所以"内核在跑"和"接管中"本来就是两件事，
/// 压成一个「连接」就必然不停出现假状态。

/// **内核真的在跑吗** —— "能不能选节点 / 看延迟 / 测速"看它。
///
/// 它**不等于**"已连接"：内核跑着但没接管流量时，延迟和测速照样可用，
/// 只是流量还没走代理。凡是需要"内核活着"的地方都必须看这个。
final coreRunningProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(hiddifyCoreServiceProvider)
      .watchStatus()
      .map((event) => event == const CoreStatus.started())
      .distinct(),
);

/// **流量被接管了吗** —— 这才是「连接」这个词的落点。
///
/// - **TUN**：只能在启动时决定，所以内核在跑就等于接管中
/// - **系统代理**：内核在跑 **且** `captureEnabled`（app 自己的开关）
/// - **仅代理**：从不接管系统流量（用户自己把程序指向入站端口）
///
/// 于是「只跑内核、不接管流量」这条路成立了：关掉 `captureEnabled` 再启动，
/// 内核对齐、延迟可测、节点可选，而流量没被接管 —— 这正是 nekoray 的体验。
final capturingProvider = Provider<bool>((ref) {
  final mode = ref.watch(ConfigOptions.serviceMode);
  final coreUp = ref.watch(coreRunningProvider).valueOrNull ?? false;
  final capture = ref.watch(Preferences.captureEnabled);
  return switch (mode) {
    ServiceMode.tun => coreUp,
    ServiceMode.systemProxy => coreUp && capture,
    ServiceMode.proxy => false,
  };
});
