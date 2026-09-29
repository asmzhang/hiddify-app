import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/utils/available_port.dart';

void main() {
  test('桌面核心端口：首选端口可绑定时保持兼容端口', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = probe.port;
    await probe.close();

    expect(await selectAvailableLoopbackPort(freePort), freePort);
  });

  test('桌面核心端口：首选端口被占或被系统保留时自动回落', () async {
    final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(occupied.close);

    final selected = await selectAvailableLoopbackPort(occupied.port);
    expect(selected, isNot(occupied.port));
    expect(selected, greaterThan(0));

    // 返回前探针已释放，native core 随后必须能绑定这个端口。
    final verification = await ServerSocket.bind(InternetAddress.loopbackIPv4, selected);
    await verification.close();
  });
}
