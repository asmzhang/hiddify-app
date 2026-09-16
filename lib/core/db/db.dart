import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:hiddify/core/db/converters/duration_converter.dart';
import 'package:hiddify/core/db/db.steps.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/per_app_proxy_mode.dart';
import 'package:hiddify/core/model/profile_type.dart';
import 'package:hiddify/core/model/proxy_group.dart';
import 'package:hiddify/utils/custom_loggers.dart';

part 'db.g.dart';

@DriftDatabase(tables: [ProfileEntries, AppProxyEntries, ProxyGroups, ProxyEntities])
class Db extends _$Db with InfraLogger {
  Db([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 7;

  static QueryExecutor _openConnection() {
    return LazyDatabase(
      () => driftDatabase(
        name: "db",
        native: const DriftNativeOptions(databaseDirectory: AppDirectories.getDatabaseDirectory),
        web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
      ),
    );
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: stepByStep(
        from1To2: (m, schema) async {
          await m.alterTable(
            TableMigration(
              schema.profileEntries,
              columnTransformer: {schema.profileEntries.type: const Constant<String>("remote")},
              newColumns: [schema.profileEntries.type],
            ),
          );
        },
        from2To3: (m, schema) async {
          await m.createTable(schema.geoAssetEntries);
        },
        from3To4: (m, schema) async {
          final testUrlExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.testUrl.name,
          );
          if (!testUrlExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.testUrl);
          }
        },
        from4To5: (m, schema) async {
          await m.deleteTable('geo_asset_entries');
          await m.renameColumn(schema.profileEntries, 'test_url', schema.profileEntries.profileOverride);
          await m.addColumn(schema.profileEntries, schema.profileEntries.userOverride);
          await m.addColumn(schema.profileEntries, schema.profileEntries.populatedHeaders);

          await m.createTable(schema.appProxyEntries);
        },
        from5To6: (m, schema) async {
          await m.dropColumn(schema.profileEntries, 'profile_override');
        },
        from6To7: (m, schema) async {
          // 实体层（照 NekoBox 的 `proxy_groups` / `proxy_entities`）。
          // 纯新增、不动既有表 —— 见 docs/design/nekobox-parity.md §8.6。
          await m.createTable(schema.proxyGroups);
          await m.createTable(schema.proxyEntities);
        },
      ),
    );
  }

  Future<bool> _columnExists(String table, String column) async {
    final result = await customSelect('PRAGMA table_info($table);').get();
    return result.any((row) => row.data['name'] == column);
  }
}

@DataClassName('ProfileEntry')
class ProfileEntries extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<ProfileType>()();
  BoolColumn get active => boolean()();
  TextColumn get name => text().withLength(min: 1)();
  TextColumn get url => text().nullable()();
  DateTimeColumn get lastUpdate => dateTime()();
  IntColumn get updateInterval => integer().nullable().map(DurationTypeConverter())();
  IntColumn get upload => integer().nullable()();
  IntColumn get download => integer().nullable()();
  IntColumn get total => integer().nullable()();
  DateTimeColumn get expire => dateTime().nullable()();
  TextColumn get webPageUrl => text().nullable()();
  TextColumn get supportUrl => text().nullable()();
  TextColumn get populatedHeaders => text().nullable()();
  TextColumn get userOverride => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AppProxyEntry')
class AppProxyEntries extends Table {
  TextColumn get mode => textEnum<AppProxyMode>()();
  TextColumn get pkgName => text()();
  IntColumn get flags => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {mode, pkgName};
}

/// 分组实体 —— 字段照 NekoBox `database/ProxyGroup.kt`（`proxy_groups` 表）。
///
/// 这是本项目此前缺的那一层：NekoBox 里分组是**一等公民**（订阅派生 或 手动新建），
/// 而本项目此前只能从订阅配置里"解析出"分组结构。有了它才谈得上手动分组、
/// 分组级排序/前置·落地代理、`createGroup`。
@DataClassName('ProxyGroupEntry')
class ProxyGroups extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 用户自定义顺序（NekoBox `userOrder`）。
  IntColumn get userOrder => integer().withDefault(const Constant(0))();

  /// 是否为系统维护的「未分组」分组（NekoBox `ungrouped`；为空时从 Tab 移除）。
  BoolColumn get ungrouped => boolean().withDefault(const Constant(false))();

  TextColumn get name => text().nullable()();

  /// 分组类型（NekoBox `type`，Int；这里 textEnum 存名）。
  TextColumn get type => textEnum<ProxyGroupType>()();

  /// 订阅详情 —— NekoBox 用 `SubscriptionBean`（Kryo）；这里存 JSON。
  /// 内容照 NekoBox `SubscriptionBean`：链接、UA、自动更新与间隔、去重、强制解析等。
  TextColumn get subscription => text().nullable()();

  /// 组内节点排序（NekoBox `order`）。**排序是分组自己的属性**，不是全局的。
  TextColumn get order => textEnum<ProxyGroupOrder>().withDefault(const Constant('origin'))();

  /// 是否把该组建成 selector（NekoBox `isSelector`；`ConfigBuilder` 据此生成 selector 出站）。
  BoolColumn get isSelector => boolean().withDefault(const Constant(false))();

  /// 前置代理（NekoBox `frontProxy`，-1 = 未设置）；此处存节点实体主键。
  IntColumn get frontProxy => integer().withDefault(const Constant(-1))();

  /// 落地代理（NekoBox `landingProxy`，-1 = 未设置）；此处存节点实体主键。
  IntColumn get landingProxy => integer().withDefault(const Constant(-1))();
}

/// 节点实体 —— 字段照 NekoBox `database/ProxyEntity.kt`（`proxy_entities` 表）。
///
/// 它让节点在应用侧成为一等公民：可编辑、可手动新建、可删除、可作为前置/落地代理被引用。
///
/// 与 NekoBox 的两处差异（语义等价，见 docs/design/nekobox-parity.md §8.6.5）：
/// 1. NekoBox 每个协议一个 Bean 列（Kryo 二进制）；这里统一一个 [payload] JSON 列，
///    内容即**完整出站定义（含凭据）** —— 与内核 `Parse` 产出的出站 JSON 同构。
/// 2. NekoBox 用 `uuid` 列存节点标识；这里用 [tag]（配置里的出站 tag），另有 [displayName]。
@DataClassName('ProxyEntityEntry')
@TableIndex(name: 'proxy_entities_group_id', columns: {#groupId})
class ProxyEntities extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属分组（NekoBox `groupId`，带索引）。
  IntColumn get groupId => integer()();

  /// 出站 tag（配置内唯一标识）。
  TextColumn get tag => text()();

  /// 协议类型（anytls / vless / hysteria2 / …）；NekoBox 用 Int 类型号。
  TextColumn get type => text()();

  /// 显示名（对标 NekoBox 的 `displayName()`，去掉 `§` 后缀）。
  TextColumn get displayName => text()();

  /// 组内顺序（NekoBox `userOrder`）。
  IntColumn get userOrder => integer().withDefault(const Constant(0))();

  /// 累计上行/下行（NekoBox `tx` / `rx`）。
  IntColumn get tx => integer().withDefault(const Constant(0))();
  IntColumn get rx => integer().withDefault(const Constant(0))();

  /// 测速状态与延迟（NekoBox `status` / `ping`）。
  IntColumn get status => integer().withDefault(const Constant(0))();
  IntColumn get ping => integer().withDefault(const Constant(0))();

  /// 最近一次错误（NekoBox `error`，可空）。
  TextColumn get error => text().nullable()();

  /// **完整出站定义（含凭据）** —— 对标 NekoBox 的协议 Bean。
  TextColumn get payload => text()();
}
