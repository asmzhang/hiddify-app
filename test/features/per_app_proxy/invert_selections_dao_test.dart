// L1 行为测试 —— `AppProxyDao.invertSelections` 1:1 对照 NekoBox
// `AppListActivity.kt:241-259` 的 `R.id.action_invert_selections`：
//
//   runOnDefaultDispatcher {
//     for (app in apps) {
//       if (proxiedUids.contains(app.uid)) proxiedUids.delete(app.uid)
//       else proxiedUids[app.uid] = true
//     }
//     DataStore.routePackages = apps.filter { isProxiedApp(it) }.joinToString("\n") { it.packageName }
//     apps = apps.sortedWith(compareBy({ !isProxiedApp(it) }, { it.name.toString() }))
//     ...
//   }
//
// 三条从 NekoBox 语义直接推出的契约（本文件的断言主线）：
//  ① 遍历的是 **apps 全集**（`cachedApps` = 全部已安装应用，含系统应用）。
//     「隐藏系统应用」(`showSystemApps`) 只过滤 adapter 的 filteredApps，
//     从不缩小 apps ⇒ 反选必须打全量，收 `phonePkgs` 而不是可见子集。
//  ② 对**没有条目**的包，`proxiedUids[key] = true` 也会置成选中 ⇒ 无行的包
//     反选后必须落成 userSelection（= 已勾选），不能"因为没行就跳过"。
//  ③ 勾选态判据是「当前是否 proxied」——本项目勾选态由 [PkgFlag.checkboxValue]
//     决定（forceDeselection 优先），所以 flag=3（userSelection|forceDeselection）
//     显示的是**未勾选**，反选后必须变已勾选（旧判据按位判会翻成 2 = 依旧未勾选）。
//
// 另加两条本项目约束：
//  ④ 只动传入的 phonePkgs —— NekoBox 重写 routePackages 会顺手丢弃已卸载包的行，
//     本项目按 §3.0 既定差异保留历史行（它们不参与显示），反选不得误删。
//  ⑤ 另一个模式（include / exclude）的行不受影响。
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/per_app_proxy/data/app_proxy_data_source.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

Future<void> _seed(Db db, AppProxyMode mode, String pkg, int flags) {
  return db
      .into(db.appProxyEntries)
      .insert(AppProxyEntriesCompanion.insert(mode: mode, pkgName: pkg, flags: Value(flags)));
}

Future<Map<String, int>> _flagsOf(Db db, AppProxyMode mode) async {
  final rows = await (db.select(db.appProxyEntries)..where((t) => t.mode.equalsValue(mode))).get();
  return {for (final row in rows) row.pkgName: row.flags};
}

void main() {
  late Db db;
  late AppProxyDao dao;

  setUp(() {
    db = Db(NativeDatabase.memory());
    dao = AppProxyDao(db);
  });

  tearDown(() => db.close());

  test('① 遍历全量 phonePkgs：传入集合里的每个包都被翻转（含当前不可见的）', () async {
    // 「隐藏系统应用」只影响显示，反选照样要打系统应用。
    await _seed(db, AppProxyMode.include, 'com.user.a', PkgFlag.userSelection.value);
    await _seed(db, AppProxyMode.include, 'com.system.b', 0);

    await dao.invertSelections(
      phonePkgs: {'com.user.a', 'com.system.b', 'com.user.c'},
      mode: AppProxyMode.include,
    );

    final flags = await _flagsOf(db, AppProxyMode.include);
    expect(flags['com.user.a'], PkgFlag.forceDeselection.value, reason: '已勾选 → 反选成未勾选');
    expect(flags['com.system.b'], PkgFlag.userSelection.value, reason: '无勾选态 → 反选成已勾选');
    expect(flags['com.user.c'], PkgFlag.userSelection.value, reason: '列表里还没有的包也要被翻成已勾选');
  });

  test('② 没有条目的包必须新建行（NekoBox 对未知 uid 也置 selected）', () async {
    await dao.invertSelections(phonePkgs: {'com.absent'}, mode: AppProxyMode.include);

    final flags = await _flagsOf(db, AppProxyMode.include);
    expect(flags, {'com.absent': PkgFlag.userSelection.value});
  });

  test('③ 勾选态判据 = 可见勾选态：flag=3（userSelection|forceDeselection）翻成已勾选', () async {
    // 3 的可见态是「未勾选」（forceDeselection 优先），按位判据会翻成 2 —— 可见态没变。
    await _seed(db, AppProxyMode.include, 'flag3', 3);
    await _seed(db, AppProxyMode.include, 'flag2', 2);
    await _seed(db, AppProxyMode.include, 'flag0', 0);

    await dao.invertSelections(phonePkgs: {'flag3', 'flag2', 'flag0'}, mode: AppProxyMode.include);

    final flags = await _flagsOf(db, AppProxyMode.include);
    expect(flags['flag3'], PkgFlag.userSelection.value, reason: '可见态 false→true');
    expect(flags['flag2'], PkgFlag.userSelection.value, reason: '可见态 true→false');
    expect(flags['flag0'], PkgFlag.userSelection.value);
  });

  test('③b autoSelection 位保留（反选只动用户选择，不夺走自动选择的记账）', () async {
    await _seed(db, AppProxyMode.include, 'autoOnly', PkgFlag.autoSelection.value);
    await _seed(
      db,
      AppProxyMode.include,
      'autoUser',
      PkgFlag.autoSelection.value | PkgFlag.userSelection.value,
    );

    await dao.invertSelections(phonePkgs: {'autoOnly', 'autoUser'}, mode: AppProxyMode.include);

    final flags = await _flagsOf(db, AppProxyMode.include);
    expect(PkgFlag.autoSelection.check(flags['autoOnly']!), isTrue, reason: 'auto 位必须原样保留');
    expect(flags['autoOnly'], PkgFlag.autoSelection.value | PkgFlag.userSelection.value);
    expect(PkgFlag.autoSelection.check(flags['autoUser']!), isTrue);
    expect(flags['autoUser'], PkgFlag.autoSelection.value | PkgFlag.forceDeselection.value);
  });

  test('④ 只动 phonePkgs：已卸载包的历史行不被删（本项目既定差异）', () async {
    await _seed(db, AppProxyMode.include, 'com.installed', 0);
    await _seed(db, AppProxyMode.include, 'com.uninstalled', PkgFlag.userSelection.value);

    await dao.invertSelections(phonePkgs: {'com.installed'}, mode: AppProxyMode.include);

    final flags = await _flagsOf(db, AppProxyMode.include);
    expect(flags['com.installed'], PkgFlag.userSelection.value);
    expect(
      flags['com.uninstalled'],
      PkgFlag.userSelection.value,
      reason: '未安装包的历史行必须原样保留（NekoBox 会丢弃，本项目有意不同）',
    );
  });

  test('⑤ 只动当前模式：另一个模式的行不受影响', () async {
    await _seed(db, AppProxyMode.include, 'com.a', 0);
    await _seed(db, AppProxyMode.exclude, 'com.a', 0);

    await dao.invertSelections(phonePkgs: {'com.a'}, mode: AppProxyMode.include);

    expect((await _flagsOf(db, AppProxyMode.include))['com.a'], PkgFlag.userSelection.value);
    expect((await _flagsOf(db, AppProxyMode.exclude))['com.a'], 0, reason: 'exclude 模式的行不该被 include 的反选碰到');
  });

  test('空集合 = 空转（NekoBox 在 apps 未加载时循环体不执行）', () async {
    await _seed(db, AppProxyMode.include, 'com.a', 0);

    await dao.invertSelections(phonePkgs: const {}, mode: AppProxyMode.include);

    expect((await _flagsOf(db, AppProxyMode.include))['com.a'], 0);
  });

  test('反选两次回到原值（1/2、5/6 自反）', () async {
    for (final (pkg, flag) in [('p1', 1), ('p2', 2), ('p5', 5), ('p6', 6)]) {
      await _seed(db, AppProxyMode.include, pkg, flag);
    }

    await dao.invertSelections(phonePkgs: {'p1', 'p2', 'p5', 'p6'}, mode: AppProxyMode.include);
    await dao.invertSelections(phonePkgs: {'p1', 'p2', 'p5', 'p6'}, mode: AppProxyMode.include);

    final flags = await _flagsOf(db, AppProxyMode.include);
    expect(flags, {'p1': 1, 'p2': 2, 'p5': 5, 'p6': 6});
  });
}
