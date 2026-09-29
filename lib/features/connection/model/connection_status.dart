import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';

part 'connection_status.freezed.dart';

/// NekoBox 复刻 · FAB/仪表盘用的四态展示枚举。
/// 与 [ConnectionStatus] 的映射关系见 proxies_overview_page。
enum NkConnectionState { disconnected, connecting, connected, error }

enum ConnectionFabVisual { stopped, connecting, connected, stopping }

enum ConnectionFabAction { connect, stop }

class ConnectionFabSpec {
  const ConnectionFabSpec({required this.visual, required this.action, required this.enabled});

  final ConnectionFabVisual visual;
  final ConnectionFabAction action;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is ConnectionFabSpec && other.visual == visual && other.action == action && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(visual, action, enabled);
}

/// NekoBox `ServiceButton.changeState` / `BaseService.State` 的可见交互投影。
ConnectionFabSpec connectionFabSpec(ConnectionStatus? status) => switch (status) {
  null => const ConnectionFabSpec(
    visual: ConnectionFabVisual.stopped,
    action: ConnectionFabAction.connect,
    enabled: false,
  ),
  Disconnected() => const ConnectionFabSpec(
    visual: ConnectionFabVisual.stopped,
    action: ConnectionFabAction.connect,
    enabled: true,
  ),
  Connecting() => const ConnectionFabSpec(
    visual: ConnectionFabVisual.connecting,
    action: ConnectionFabAction.stop,
    enabled: true,
  ),
  Connected() => const ConnectionFabSpec(
    visual: ConnectionFabVisual.connected,
    action: ConnectionFabAction.stop,
    enabled: true,
  ),
  Disconnecting() => const ConnectionFabSpec(
    visual: ConnectionFabVisual.stopping,
    action: ConnectionFabAction.connect,
    enabled: false,
  ),
};

/// NekoBox 的 `serviceState.started` 只在 Connecting / Connected 为真。
bool connectionNodeInUse(ConnectionStatus? status) => status is Connecting || status is Connected;

@freezed
sealed class ConnectionStatus with _$ConnectionStatus {
  const ConnectionStatus._();

  const factory ConnectionStatus.disconnected([ConnectionFailure? connectionFailure]) = Disconnected;
  const factory ConnectionStatus.connecting() = Connecting;
  const factory ConnectionStatus.connected() = Connected;
  const factory ConnectionStatus.disconnecting() = Disconnecting;

  bool get isConnected => switch (this) {
    Connected() => true,
    _ => false,
  };

  bool get isDisconnected => switch (this) {
    Disconnected() => true,
    _ => false,
  };

  bool get isSwitching => switch (this) {
    Connecting() => true,
    Disconnecting() => true,
    _ => false,
  };

  String format() => switch (this) {
    Disconnected(:final connectionFailure) =>
      connectionFailure != null ? "CONNECTION FAILURE: $connectionFailure" : "DISCONNECTED",
    Connecting() => "CONNECTING",
    Connected() => "CONNECTED",
    Disconnecting() => "DISCONNECTING",
  };

  /// 状态就是状态：未连接就说「未连接」，「点击连接」是动作提示、不该拿来当状态词。
  String present(TranslationsEn t) => switch (this) {
    Disconnected() => t.connection.disconnected,
    Connecting() => t.connection.connecting,
    Connected() => t.connection.connected,
    Disconnecting() => t.connection.disconnecting,
  };
}
