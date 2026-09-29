import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';

/// NekoBox `ServiceButton` 的 Flutter 等价物：纸飞机四态 + 可停止 Connecting。
class ConnectionFab extends StatelessWidget {
  const ConnectionFab({super.key, required this.status, required this.onPressed, required this.t});

  final ConnectionStatus? status;
  final VoidCallback onPressed;
  final TranslationsEn t;

  @override
  Widget build(BuildContext context) {
    final spec = connectionFabSpec(status);
    final foreground =
        Theme.of(context).floatingActionButtonTheme.foregroundColor ?? Theme.of(context).colorScheme.onPrimary;
    return FloatingActionButton(
      onPressed: spec.enabled ? onPressed : null,
      tooltip: spec.action == ConnectionFabAction.stop ? t.connection.stop : t.connection.connect,
      child: switch (spec.visual) {
        ConnectionFabVisual.stopped => _StoppedIcon(color: foreground),
        ConnectionFabVisual.connecting => _ProgressIcon(color: foreground),
        ConnectionFabVisual.connected => const Icon(FluentIcons.send_24_filled),
        ConnectionFabVisual.stopping => _ProgressIcon(color: foreground),
      },
    );
  }
}

class _ProgressIcon extends StatelessWidget {
  const _ProgressIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      const Icon(FluentIcons.send_24_regular, size: 20),
      SizedBox.square(dimension: 34, child: CircularProgressIndicator(strokeWidth: 2.4, color: color)),
    ],
  );
}

class _StoppedIcon extends StatelessWidget {
  const _StoppedIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      const Icon(FluentIcons.send_24_regular),
      Transform.rotate(
        angle: -math.pi / 4,
        child: Container(width: 30, height: 2, color: color),
      ),
    ],
  );
}
