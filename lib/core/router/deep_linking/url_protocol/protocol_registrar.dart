// 把 [protocolRegistrationAction] 的判定落到平台上。
//
// 拆成独立一层（而不是塞进 `my_app_links.dart`）有两个理由：
//   1. 注册表读写是平台副作用，必须能被假 handler 替换后单测；
//   2. 「一次失败不能让整个流程断掉」是这里的核心语义 —— 7 个 scheme 里
//      任何一个的注册表操作被拒（组策略、企业环境、另一个用户 hive），
//      都只该是那一个 scheme 放弃，绝不能抛出把 deep link 全流程带走。
//
// 与 `lib/features/auto_start/notifier/auto_start_notifier.dart` 的 `_guard`
// 同一套降级纪律：平台操作失败 ⇒ 记日志 + 当作"没做成"，不抛。
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol_registration_spec.dart';
import 'package:hiddify/utils/custom_loggers.dart';

/// 一次 reconcile 的结果，供测试与诊断使用。
typedef ProtocolReconcileReport = ({
  List<String> claimed,
  List<String> kept,
  List<String> revoked,
  List<String> left,
  List<String> failed,
});

class ProtocolRegistrar with InfraLogger {
  const ProtocolRegistrar(this.handler);

  final ProtocolHandler handler;

  /// 按 [kAllProtocolSchemes] 逐个校准协议关联。
  ///
  /// 幂等：稳态下（已经注册对了）产生 0 次写操作。返回的报告里
  /// [ProtocolReconcileReport.claimed] / [ProtocolReconcileReport.revoked]
  /// 都为空就是"什么都没改"。
  ProtocolReconcileReport reconcile() {
    final claimed = <String>[];
    final kept = <String>[];
    final revoked = <String>[];
    final left = <String>[];
    final failed = <String>[];

    if (!handler.supportsAssociation) {
      // Web / 移动端：本就不存在协议关联，整段跳过（不是失败）。
      return (
        claimed: claimed,
        kept: kept,
        revoked: revoked,
        left: left,
        failed: failed,
      );
    }

    for (final scheme in kAllProtocolSchemes) {
      try {
        final action = protocolRegistrationAction(
          scheme: scheme,
          registeredCommand: handler.registeredCommand(scheme),
          executable: handler.executable,
        );

        switch (action) {
          case ProtocolRegistrationAction.claim:
            handler.register(scheme);
            claimed.add(scheme);
          case ProtocolRegistrationAction.keep:
            kept.add(scheme);
          case ProtocolRegistrationAction.revoke:
            handler.unregister(scheme);
            revoked.add(scheme);
          case ProtocolRegistrationAction.leave:
            left.add(scheme);
        }
      } catch (e, stackTrace) {
        // 单个 scheme 失败不影响其余：注册表权限、畸形值、平台异常都走这里。
        failed.add(scheme);
        loggy.warning(
          "protocol association [$scheme] failed, leaving system state untouched",
          e,
          stackTrace,
        );
      }
    }

    if (revoked.isNotEmpty) {
      // 归还命名空间是刻意行为，留一条可见记录（用户可能好奇注册表为什么变了）。
      loggy.info("released foreign protocol schemes: [${revoked.join(', ')}]");
    }
    if (claimed.isNotEmpty) {
      loggy.debug("claimed protocol schemes: [${claimed.join(', ')}]");
    }

    return (
      claimed: claimed,
      kept: kept,
      revoked: revoked,
      left: left,
      failed: failed,
    );
  }
}
