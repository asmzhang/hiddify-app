import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 一条通道（走代理 / 走直连）的累计用量与当前速率。
class TrafficChannel {
  const TrafficChannel({
    this.up = 0,
    this.down = 0,
    this.upRate = 0,
    this.downRate = 0,
    this.measured = false,
  });

  final int up;
  final int down;
  final double upRate;
  final double downRate;

  /// false 表示还没有拿到两次采样，速率此时没有意义（不是 0 而是"未知"）。
  final bool measured;

  int get total => up + down;
  double get rate => upRate + downRate;
}

/// 总流量按"经过代理的 / 直接出去的"拆开。
///
/// 为什么这个拆分是精确的而不是估算，见 `hiddify-core/v2/hcore/proxy_info.go`
/// 里 `AllProxiesInfoStream` 的注释：核心把 `PushUploaded` 与
/// `PushOutboundUploaded` 放在同一个回调里成对调用，而 `SystemInfo` 的总量取的
/// 就是同一个 `trafficontrol.Manager` 的 `Total()`，于是
///
///     Σ(各真实出口的用量) == SystemInfo 的总量
///
/// 是个恒等式 —— 代理部分直接求和拿到，直连部分用总量减出来即可，不引入任何假设。
class TrafficSplit {
  const TrafficSplit({
    required this.proxied,
    required this.direct,
    this.totalUp = 0,
    this.totalDown = 0,
    this.totalRate = 0,
  });

  static const empty = TrafficSplit(proxied: TrafficChannel(), direct: TrafficChannel());

  final TrafficChannel proxied;
  final TrafficChannel direct;
  final int totalUp;
  final int totalDown;
  final double totalRate;

  int get total => totalUp + totalDown;

  /// 代理在总流量里的占比，0~1。总量为 0 时返回 0。
  double get proxiedFraction {
    final t = total;
    if (t <= 0) return 0;
    return (proxied.total / t).clamp(0.0, 1.0);
  }

  bool get isEmpty => total <= 0 && proxied.total <= 0 && direct.total <= 0;
}

/// 未连接时返回 [TrafficSplit.empty]。
///
/// 速率由相邻两次采样做差得到，所以这个 notifier 需要自己留一份上一次的样本
/// （`Notifier` 实例在 provider 存活期间是复用的，字段不会被 build() 重置）。
final trafficSplitProvider = AutoDisposeNotifierProvider<TrafficSplitNotifier, TrafficSplit>(
  TrafficSplitNotifier.new,
);

class TrafficSplitNotifier extends AutoDisposeNotifier<TrafficSplit> {
  int _lastProxiedUp = 0;
  int _lastProxiedDown = 0;
  int _lastDirectUp = 0;
  int _lastDirectDown = 0;
  int _lastTotalUp = 0;
  int _lastTotalDown = 0;
  DateTime? _sampledAt;

  @override
  TrafficSplit build() {
    if (!ref.watch(serviceRunningProvider)) {
      _forget();
      return TrafficSplit.empty;
    }

    final stats = ref.watch(statsNotifierProvider).asData?.value;
    final group = ref.watch(proxiesOverviewNotifierProvider).asData?.value;

    var proxiedUp = 0;
    var proxiedDown = 0;
    if (group != null) {
      for (final item in group.items) {
        // 分组自身的用量恒为 0：核心只会把字节记在链路末端那个真实出口上。
        // 带 §hide§ 的是 direct/bypass 这类内部出口，本来就不该算进"走代理"。
        if (item.isGroup || item.tag.contains('§hide§')) continue;
        proxiedUp += item.upload.toInt();
        proxiedDown += item.download.toInt();
      }
    }

    final totalUp = stats?.uplinkTotal.toInt() ?? proxiedUp;
    final totalDown = stats?.downlinkTotal.toInt() ?? proxiedDown;
    final directUp = _nonNegativeDiff(totalUp, proxiedUp);
    final directDown = _nonNegativeDiff(totalDown, proxiedDown);

    final now = DateTime.now();
    final elapsed = _sampledAt == null ? null : now.difference(_sampledAt!);
    final seconds = elapsed == null ? 0.0 : elapsed.inMilliseconds / 1000;

    double rate(int current, int previous) {
      // 计数器只会涨；万一因为重连而回退，就当作这一拍没有速率，别报负数。
      if (seconds <= 0 || current < previous) return 0;
      return (current - previous) / seconds;
    }

    final measured = elapsed != null && seconds > 0;
    final split = TrafficSplit(
      proxied: TrafficChannel(
        up: proxiedUp,
        down: proxiedDown,
        upRate: rate(proxiedUp, _lastProxiedUp),
        downRate: rate(proxiedDown, _lastProxiedDown),
        measured: measured,
      ),
      direct: TrafficChannel(
        up: directUp,
        down: directDown,
        upRate: rate(directUp, _lastDirectUp),
        downRate: rate(directDown, _lastDirectDown),
        measured: measured,
      ),
      totalUp: totalUp,
      totalDown: totalDown,
      totalRate: rate(totalUp, _lastTotalUp) + rate(totalDown, _lastTotalDown),
    );

    _lastProxiedUp = proxiedUp;
    _lastProxiedDown = proxiedDown;
    _lastDirectUp = directUp;
    _lastDirectDown = directDown;
    _lastTotalUp = totalUp;
    _lastTotalDown = totalDown;
    _sampledAt = now;

    return split;
  }

  static int _nonNegativeDiff(int total, int part) => total > part ? total - part : 0;

  void _forget() {
    _lastProxiedUp = 0;
    _lastProxiedDown = 0;
    _lastDirectUp = 0;
    _lastDirectDown = 0;
    _lastTotalUp = 0;
    _lastTotalDown = 0;
    _sampledAt = null;
  }
}
