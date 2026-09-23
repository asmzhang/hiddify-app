// L1 结构对等测试 —— 分组设置表单（NekoBox `GroupSettingsActivity` 对位）。
// 规格映射与架构差异见 `group_settings_sheet.dart` 头注释；词表基准 zh-CN：
//   group_settings=分组设置  group_name=分组名  save=保存  delete=删除。
// 本项目差异键：subscriptionHint（订阅链接/自动更新在订阅页管理 —— 归一原则）。
//
// 测试坑：一个用例里二次 pumpWidget 会有旧 overlay 残留/状态串扰（实证），
// 且保存后 sheet 自动 pop —— 所以每个流程独立用例、每用例只开一次 sheet。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/overview/group_settings_sheet.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) =>
    tester.runAsync(() => AppLocale.zhCn.build());

/// 经 showDialog 打开（与页面同路径），保证 Navigator.pop 语义真实。
Future<void> _pump(
  WidgetTester tester, {
  required bool isSubscription,
  required List<String> saveLog,
  required List<String> deleteLog,
  String initialName = '云菁',
  VoidCallback? onOpenSubscriptions,
}) async {
  final t = await _loadZhCn(tester);
  final container = ProviderContainer(overrides: [
    translationsProvider.overrideWith((ref) => Future.value(t)),
  ]);
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (sheetContext) => NkGroupSettingsSheet(
                    initialName: initialName,
                    isSubscription: isSubscription,
                    onSave: (name) async => saveLog.add(name),
                    onDelete: () async {
                      deleteLog.add('deleted');
                      return true;
                    },
                    onOpenSubscriptions: onOpenSubscriptions,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('结构：标题=分组设置 + 名称预填 + 保存/删除动作', (tester) async {
    final saveLog = <String>[];
    final deleteLog = <String>[];
    await _pump(tester, isSubscription: false, saveLog: saveLog, deleteLog: deleteLog);

    expect(find.text('分组设置'), findsOneWidget, reason: '标题 = NekoBox R.string.group_settings');
    expect(find.text('分组名'), findsOneWidget, reason: '字段 label = group_name 词表');
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget, reason: 'spec action_delete 的危险动作入口');
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '云菁');
  });

  testWidgets('改名 → 保存 → onSave 收到 trim 后的新名，sheet 自动关闭', (tester) async {
    final saveLog = <String>[];
    await _pump(tester, isSubscription: false, saveLog: saveLog, deleteLog: []);

    await tester.enterText(find.byType(TextField), '  新组名  ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saveLog, ['新组名'], reason: '保存前 trim');
    expect(find.text('分组设置'), findsNothing, reason: '保存成功后 sheet 自行关闭');
  });

  testWidgets('删除 → onDelete 被调用', (tester) async {
    final deleteLog = <String>[];
    await _pump(tester, isSubscription: false, saveLog: [], deleteLog: deleteLog);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(deleteLog, ['deleted'], reason: '确认框在页面侧，这里直接真值');
  });

  testWidgets('空名不触发保存', (tester) async {
    final saveLog = <String>[];
    await _pump(tester, isSubscription: false, saveLog: saveLog, deleteLog: []);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saveLog, isEmpty, reason: '空名不许保存');
  });

  testWidgets('订阅组显示提示行（链接/自动更新在订阅页管理）', (tester) async {
    await _pump(tester, isSubscription: true, saveLog: [], deleteLog: []);
    expect(find.text('订阅链接与自动更新在「订阅」页管理'), findsOneWidget,
        reason: '归一原则：订阅字段入口唯一，指向订阅页');
  });

  testWidgets('订阅组提示行可点 → 触发打开订阅管理（可达性闭环）', (tester) async {
    var opened = false;
    await _pump(tester, isSubscription: true, saveLog: [], deleteLog: [], onOpenSubscriptions: () => opened = true);

    await tester.tap(find.text('订阅链接与自动更新在「订阅」页管理'));
    await tester.pumpAndSettle();
    expect(opened, isTrue, reason: '功能②遗留可达性修复：提示行 = 订阅页入口');
  });

  testWidgets('无回调时提示行不可点', (tester) async {
    await _pump(tester, isSubscription: true, saveLog: [], deleteLog: []);
    // ElevatedButton 内部也有 InkWell —— 用提示文本的祖先精确定位。
    final hintInkWell = find.ancestor(
      of: find.text('订阅链接与自动更新在「订阅」页管理'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(hintInkWell.first).onTap, isNull);
  });

  testWidgets('手动组无提示行', (tester) async {
    await _pump(tester, isSubscription: false, saveLog: [], deleteLog: []);
    expect(find.text('订阅链接与自动更新在「订阅」页管理'), findsNothing);
  });
}
