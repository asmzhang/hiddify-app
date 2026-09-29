import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/model/proxy_group.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockPathResolver extends Mock implements ProfilePathResolver {}

class _MockCoreService extends Mock implements HiddifyCoreService {}

ImportedProxyEntity _entity(String tag, {String type = 'vless'}) => ImportedProxyEntity(
  tag: tag,
  type: type,
  displayName: tag.split(' §').first,
  payload: '{"type":"$type","tag":"$tag","server":"example.com","server_port":443}',
);

void main() {
  late Db db;
  late ProxyEntityRepository repository;

  setUp(() {
    db = Db(NativeDatabase.memory());
    repository = ProxyEntityRepository(db: db, pathResolver: _MockPathResolver(), singbox: _MockCoreService());
  });

  tearDown(() => db.close());

  test('selectedGroupForImport 只接受 BASIC，按 userOrder 回落并可懒建未分组', () async {
    final subscriptionId = await db
        .into(db.proxyGroups)
        .insert(ProxyGroupsCompanion.insert(type: ProxyGroupType.subscription, name: const Value('sub')));
    final laterBasic = await repository.createGroup(name: 'later');
    final firstBasic = await repository.createGroup(name: 'first');
    await (db.update(
      db.proxyGroups,
    )..where((t) => t.id.equals(firstBasic!))).write(const ProxyGroupsCompanion(userOrder: Value(-1)));

    expect(await repository.selectedGroupForImport(subscriptionId), firstBasic);
    expect(await repository.selectedGroupForImport(999999), firstBasic);
    expect(await repository.selectedGroupForImport(laterBasic), laterBasic);

    await (db.delete(db.proxyGroups)..where((t) => t.id.isIn([laterBasic!, firstBasic!]))).go();
    final created = await repository.selectedGroupForImport(null);
    final group = await (db.select(db.proxyGroups)..where((t) => t.id.equals(created!))).getSingle();
    expect(group.type, ProxyGroupType.basic);
    expect(group.ungrouped, isTrue);
  });

  test('importNodes 原子写入并在任一 tag 冲突时整批回滚', () async {
    final groupId = (await repository.createGroup(name: 'manual'))!;
    final imported = await repository.importNodes(
      groupId: groupId,
      entities: [
        _entity('A § 0'),
        _entity('B § 1', type: 'trojan'),
      ],
    );
    expect(imported, 2);
    final rows = await (db.select(db.proxyEntities)..where((t) => t.groupId.equals(groupId))).get();
    expect(rows.map((e) => e.tag), ['A § 0', 'B § 1']);
    expect(rows.map((e) => e.displayName), ['A', 'B']);
    expect(rows.map((e) => e.userOrder), [0, 1]);

    final failed = await repository.importNodes(groupId: groupId, entities: [_entity('C § 2'), _entity('A § 0')]);
    expect(failed, -1);
    final after = await db.select(db.proxyEntities).get();
    expect(after.map((e) => e.tag), isNot(contains('C § 2')));
    expect(after, hasLength(2));
  });

  test('importNodes 拒绝订阅组', () async {
    final subscriptionId = await db
        .into(db.proxyGroups)
        .insert(ProxyGroupsCompanion.insert(type: ProxyGroupType.subscription, name: const Value('sub')));
    expect(await repository.importNodes(groupId: subscriptionId, entities: [_entity('A § 0')]), -1);
    expect(await db.select(db.proxyEntities).get(), isEmpty);
  });
}
