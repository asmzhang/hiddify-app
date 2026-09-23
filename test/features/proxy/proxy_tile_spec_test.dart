// L1 结构对等测试 —— 节点卡状态位（NekoBox `ConfigurationFragment.kt:1565-1592`
// 的纯函数投影，见 `proxy_tile_spec.dart`）。词表基准 zh-CN。
//
// 关键规格：
// - 未测速（delay<=0）时**流量文本挪到状态位**（L1565-1572），无流量 = 空字符串
//   （此前实现是 "—" 占位 —— 1:1 修正点）。
// - 错误编码（<0）→ connection_test_* 文案（zh-rCN：连接被拒绝/超时/无法访问/域名不存在）。
// - 已测速 → 延迟毫秒；超时阈值 → '×'。
// - 行2 流量显隐 = hasTraffic && tested（两处只显示一处）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile_spec.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) =>
    tester.runAsync(() => AppLocale.zhCn.build());

void main() {
  late Translations t;
  const error = Color(0xFFB3261E);
  const tested = Color(0xFF2E7D32);
  const neutral = Color(0xFF616161);

  testWidgets('状态位分支全表', (tester) async {
    t = (await _loadZhCn(tester))!;

    // 组行：显示当前选中项（架构差异条目，非 spec；trim 在调用点做）。
    expect(
      nkProxyStatus(t, isGroup: true, groupSelectedTagDisplay: 'HK-01', delay: 0, traffic: null, errorColor: error, testedColor: tested, neutralColor: neutral),
      (text: 'HK-01', color: neutral),
    );

    // 错误编码 → connection_test_* 文案 + 错误色。
    expect(
      nkProxyStatus(t, isGroup: false, groupSelectedTagDisplay: '', delay: -1, traffic: null, errorColor: error, testedColor: tested, neutralColor: neutral).text,
      t.pages.proxies.msg.testRefused,
    );
    expect(
      nkProxyStatus(t, isGroup: false, groupSelectedTagDisplay: '', delay: -3, traffic: null, errorColor: error, testedColor: tested, neutralColor: neutral).text,
      t.pages.proxies.msg.testTimeout,
    );
    expect(
      nkProxyStatus(t, isGroup: false, groupSelectedTagDisplay: '', delay: -5, traffic: null, errorColor: error, testedColor: tested, neutralColor: neutral).color,
      error,
    );

    // 未测速 + 有流量 → 流量文本挪到状态位。
    expect(
      nkProxyStatus(t, isGroup: false, groupSelectedTagDisplay: '', delay: 0, traffic: '↑ 1 B ↓ 2 B', errorColor: error, testedColor: tested, neutralColor: neutral),
      (text: '↑ 1 B ↓ 2 B', color: neutral),
    );

    // 未测速 + 无流量 → **空字符串**（1:1 修正点：此前是 "—"）。
    expect(
      nkProxyStatus(t, isGroup: false, groupSelectedTagDisplay: '', delay: 0, traffic: null, errorColor: error, testedColor: tested, neutralColor: neutral).text,
      '',
    );

    // 已测速 → 毫秒数；超时阈值 → '×'。
    final ok = nkProxyStatus(t, isGroup: false, groupSelectedTagDisplay: '', delay: 200, traffic: null, errorColor: error, testedColor: tested, neutralColor: neutral);
    expect(ok.text, '200');
    expect(ok.color, tested);
    final timeout = nkProxyStatus(t, isGroup: false, groupSelectedTagDisplay: '', delay: timeoutOver, traffic: null, errorColor: error, testedColor: tested, neutralColor: neutral);
    expect(timeout.text, '×');
  });

  testWidgets('行2 流量显隐：只有已测速才在行2 显示（未测速时流量在状态位）', (tester) async {
    t = (await _loadZhCn(tester))!;
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: true, tested: true), isTrue);
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: true, tested: false), isFalse, reason: '未测速时流量挪到状态位（L1567-1569）');
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: false, tested: true), isFalse);
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: false, tested: false), isFalse);
  });
}

/// 超过超时阈值的哨兵值（避免测试直接依赖 NkColors 内部阈值常量）。
const timeoutOver = 1 << 30;
