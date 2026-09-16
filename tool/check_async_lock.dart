// `SerialAsyncLock` 的可执行校验。
//
// 运行：dart run tool/check_async_lock.dart
//
// 要证明的核心：不重叠 / 保序 / **一次失败不破坏锁**。
// 第三条是这类实现最经典的坑：把失败的 Future 当链尾会让后续任务永久排队，
// 表现为功能无声卡死（比崩溃更难查）。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/utils/serial_async_lock.dart';

Future<void> main() async {
  var failures = 0;

  // List/Map 在 Dart 里 == 是同一性比较，必须按值比 —— 否则会打印出两行一模一样的内容
  // 却判 FAIL（这个脚本第一版就是这么错的）。
  void check(String label, Object? actual, Object? expected) {
    bool eq(Object? a, Object? b) {
      if (a is List || a is Map || b is List || b is Map) return jsonEncode(a) == jsonEncode(b);
      return a == b;
    }

    final ok = eq(actual, expected);
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  Future<void> tick([int ms = 5]) => Future.delayed(Duration(milliseconds: ms));

  // ---- 1) 不重叠 + 保序：后请求的必须等前一个彻底跑完 ----
  {
    final lock = SerialAsyncLock();
    final events = <String>[];
    final slow = lock.run(() async {
      events.add('a-start');
      await tick(30);
      events.add('a-end');
      return 1;
    });
    final quick = lock.run(() async {
      events.add('b-start');
      events.add('b-end');
      return 2;
    });
    final results = await Future.wait([slow, quick]);
    check('不重叠且保序', events, ['a-start', 'a-end', 'b-start', 'b-end']);
    check('各自结果原样返回', results, [1, 2]);
  }

  // ---- 2) 第三个请求要排在前两个后面（验证是真队列，不是"两两互斥"） ----
  {
    final lock = SerialAsyncLock();
    final events = <String>[];
    Future<void> job(String name, int ms) => lock.run(() async {
      events.add('$name-start');
      await tick(ms);
      events.add('$name-end');
    });
    final all = Future.wait([job('x', 20), job('y', 5), job('z', 1)]);
    await all;
    check('三任务严格串行', events, ['x-start', 'x-end', 'y-start', 'y-end', 'z-start', 'z-end']);
  }

  // ---- 3) 失败不破坏锁：抛异常的任务之后，后面的任务仍然能跑 ----
  {
    final lock = SerialAsyncLock();
    final events = <String>[];
    final boom = lock.run<int>(() async => throw StateError('boom'));
    final after = lock.run<int>(() async {
      events.add('after');
      return 7;
    });

    // 失败必须原样交给调用方（而不是被锁吞掉）
    // 注意 onError 必须用**块体**：`(e) => caught = e` 是赋值表达式，返回 Object 而非 void，
    // 会撞上 "onError handler must return a value of the returned future's type"。
    Object? caught;
    await boom.then((_) {}, onError: (Object e) {
      caught = e;
    });
    check('失败原样抛给调用方', caught is StateError, true);
    // 关键：后面的任务没有被卡住
    check('失败之后锁仍可用', await after, 7);
    check('失败之后的任务确实执行了', events, ['after']);
  }

  // ---- 4) 连续多次失败之后仍然可用（链尾不被污染） ----
  {
    final lock = SerialAsyncLock();
    for (var i = 0; i < 3; i++) {
      await lock.run<void>(() async => throw StateError('boom$i')).then((_) {}, onError: (_) {});
    }
    check('连败三次后仍可用', await lock.run(() async => 'ok'), 'ok');
  }

  // ---- 5) **同步**抛出的 action（连 Future 都没返回）也要进队列并让位 ----
  {
    final lock = SerialAsyncLock();
    final events = <String>[];
    final bad = lock.run<void>(() {
      events.add('bad');
      throw StateError('thrown before returning a future');
    });
    final next = lock.run<void>(() async => events.add('next'));
    await bad.then((_) {}, onError: (_) {});
    await next;
    check('同步抛出后仍继续', events, ['bad', 'next']);
  }

  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILED');
  if (failures != 0) throw StateError('verification failed: $failures assertion(s)');
}
