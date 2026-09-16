// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class ProfileEntries extends Table
    with TableInfo<ProfileEntries, ProfileEntriesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ProfileEntries(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 1),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> lastUpdate = GeneratedColumn<DateTime>(
    'last_update',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> updateInterval = GeneratedColumn<int>(
    'update_interval',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> upload = GeneratedColumn<int>(
    'upload',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> download = GeneratedColumn<int>(
    'download',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<int> total = GeneratedColumn<int>(
    'total',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> expire = GeneratedColumn<DateTime>(
    'expire',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> webPageUrl = GeneratedColumn<String>(
    'web_page_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> supportUrl = GeneratedColumn<String>(
    'support_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> populatedHeaders = GeneratedColumn<String>(
    'populated_headers',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> userOverride = GeneratedColumn<String>(
    'user_override',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    active,
    name,
    url,
    lastUpdate,
    updateInterval,
    upload,
    download,
    total,
    expire,
    webPageUrl,
    supportUrl,
    populatedHeaders,
    userOverride,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_entries';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileEntriesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileEntriesData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      lastUpdate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_update'],
      )!,
      updateInterval: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}update_interval'],
      ),
      upload: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}upload'],
      ),
      download: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}download'],
      ),
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total'],
      ),
      expire: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expire'],
      ),
      webPageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}web_page_url'],
      ),
      supportUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}support_url'],
      ),
      populatedHeaders: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}populated_headers'],
      ),
      userOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_override'],
      ),
    );
  }

  @override
  ProfileEntries createAlias(String alias) {
    return ProfileEntries(attachedDatabase, alias);
  }
}

class ProfileEntriesData extends DataClass
    implements Insertable<ProfileEntriesData> {
  final String id;
  final String type;
  final bool active;
  final String name;
  final String? url;
  final DateTime lastUpdate;
  final int? updateInterval;
  final int? upload;
  final int? download;
  final int? total;
  final DateTime? expire;
  final String? webPageUrl;
  final String? supportUrl;
  final String? populatedHeaders;
  final String? userOverride;
  const ProfileEntriesData({
    required this.id,
    required this.type,
    required this.active,
    required this.name,
    this.url,
    required this.lastUpdate,
    this.updateInterval,
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.webPageUrl,
    this.supportUrl,
    this.populatedHeaders,
    this.userOverride,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['active'] = Variable<bool>(active);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    map['last_update'] = Variable<DateTime>(lastUpdate);
    if (!nullToAbsent || updateInterval != null) {
      map['update_interval'] = Variable<int>(updateInterval);
    }
    if (!nullToAbsent || upload != null) {
      map['upload'] = Variable<int>(upload);
    }
    if (!nullToAbsent || download != null) {
      map['download'] = Variable<int>(download);
    }
    if (!nullToAbsent || total != null) {
      map['total'] = Variable<int>(total);
    }
    if (!nullToAbsent || expire != null) {
      map['expire'] = Variable<DateTime>(expire);
    }
    if (!nullToAbsent || webPageUrl != null) {
      map['web_page_url'] = Variable<String>(webPageUrl);
    }
    if (!nullToAbsent || supportUrl != null) {
      map['support_url'] = Variable<String>(supportUrl);
    }
    if (!nullToAbsent || populatedHeaders != null) {
      map['populated_headers'] = Variable<String>(populatedHeaders);
    }
    if (!nullToAbsent || userOverride != null) {
      map['user_override'] = Variable<String>(userOverride);
    }
    return map;
  }

  ProfileEntriesCompanion toCompanion(bool nullToAbsent) {
    return ProfileEntriesCompanion(
      id: Value(id),
      type: Value(type),
      active: Value(active),
      name: Value(name),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      lastUpdate: Value(lastUpdate),
      updateInterval: updateInterval == null && nullToAbsent
          ? const Value.absent()
          : Value(updateInterval),
      upload: upload == null && nullToAbsent
          ? const Value.absent()
          : Value(upload),
      download: download == null && nullToAbsent
          ? const Value.absent()
          : Value(download),
      total: total == null && nullToAbsent
          ? const Value.absent()
          : Value(total),
      expire: expire == null && nullToAbsent
          ? const Value.absent()
          : Value(expire),
      webPageUrl: webPageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(webPageUrl),
      supportUrl: supportUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(supportUrl),
      populatedHeaders: populatedHeaders == null && nullToAbsent
          ? const Value.absent()
          : Value(populatedHeaders),
      userOverride: userOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(userOverride),
    );
  }

  factory ProfileEntriesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileEntriesData(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      active: serializer.fromJson<bool>(json['active']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String?>(json['url']),
      lastUpdate: serializer.fromJson<DateTime>(json['lastUpdate']),
      updateInterval: serializer.fromJson<int?>(json['updateInterval']),
      upload: serializer.fromJson<int?>(json['upload']),
      download: serializer.fromJson<int?>(json['download']),
      total: serializer.fromJson<int?>(json['total']),
      expire: serializer.fromJson<DateTime?>(json['expire']),
      webPageUrl: serializer.fromJson<String?>(json['webPageUrl']),
      supportUrl: serializer.fromJson<String?>(json['supportUrl']),
      populatedHeaders: serializer.fromJson<String?>(json['populatedHeaders']),
      userOverride: serializer.fromJson<String?>(json['userOverride']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'active': serializer.toJson<bool>(active),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String?>(url),
      'lastUpdate': serializer.toJson<DateTime>(lastUpdate),
      'updateInterval': serializer.toJson<int?>(updateInterval),
      'upload': serializer.toJson<int?>(upload),
      'download': serializer.toJson<int?>(download),
      'total': serializer.toJson<int?>(total),
      'expire': serializer.toJson<DateTime?>(expire),
      'webPageUrl': serializer.toJson<String?>(webPageUrl),
      'supportUrl': serializer.toJson<String?>(supportUrl),
      'populatedHeaders': serializer.toJson<String?>(populatedHeaders),
      'userOverride': serializer.toJson<String?>(userOverride),
    };
  }

  ProfileEntriesData copyWith({
    String? id,
    String? type,
    bool? active,
    String? name,
    Value<String?> url = const Value.absent(),
    DateTime? lastUpdate,
    Value<int?> updateInterval = const Value.absent(),
    Value<int?> upload = const Value.absent(),
    Value<int?> download = const Value.absent(),
    Value<int?> total = const Value.absent(),
    Value<DateTime?> expire = const Value.absent(),
    Value<String?> webPageUrl = const Value.absent(),
    Value<String?> supportUrl = const Value.absent(),
    Value<String?> populatedHeaders = const Value.absent(),
    Value<String?> userOverride = const Value.absent(),
  }) => ProfileEntriesData(
    id: id ?? this.id,
    type: type ?? this.type,
    active: active ?? this.active,
    name: name ?? this.name,
    url: url.present ? url.value : this.url,
    lastUpdate: lastUpdate ?? this.lastUpdate,
    updateInterval: updateInterval.present
        ? updateInterval.value
        : this.updateInterval,
    upload: upload.present ? upload.value : this.upload,
    download: download.present ? download.value : this.download,
    total: total.present ? total.value : this.total,
    expire: expire.present ? expire.value : this.expire,
    webPageUrl: webPageUrl.present ? webPageUrl.value : this.webPageUrl,
    supportUrl: supportUrl.present ? supportUrl.value : this.supportUrl,
    populatedHeaders: populatedHeaders.present
        ? populatedHeaders.value
        : this.populatedHeaders,
    userOverride: userOverride.present ? userOverride.value : this.userOverride,
  );
  ProfileEntriesData copyWithCompanion(ProfileEntriesCompanion data) {
    return ProfileEntriesData(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      active: data.active.present ? data.active.value : this.active,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      lastUpdate: data.lastUpdate.present
          ? data.lastUpdate.value
          : this.lastUpdate,
      updateInterval: data.updateInterval.present
          ? data.updateInterval.value
          : this.updateInterval,
      upload: data.upload.present ? data.upload.value : this.upload,
      download: data.download.present ? data.download.value : this.download,
      total: data.total.present ? data.total.value : this.total,
      expire: data.expire.present ? data.expire.value : this.expire,
      webPageUrl: data.webPageUrl.present
          ? data.webPageUrl.value
          : this.webPageUrl,
      supportUrl: data.supportUrl.present
          ? data.supportUrl.value
          : this.supportUrl,
      populatedHeaders: data.populatedHeaders.present
          ? data.populatedHeaders.value
          : this.populatedHeaders,
      userOverride: data.userOverride.present
          ? data.userOverride.value
          : this.userOverride,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileEntriesData(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('active: $active, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('lastUpdate: $lastUpdate, ')
          ..write('updateInterval: $updateInterval, ')
          ..write('upload: $upload, ')
          ..write('download: $download, ')
          ..write('total: $total, ')
          ..write('expire: $expire, ')
          ..write('webPageUrl: $webPageUrl, ')
          ..write('supportUrl: $supportUrl, ')
          ..write('populatedHeaders: $populatedHeaders, ')
          ..write('userOverride: $userOverride')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    active,
    name,
    url,
    lastUpdate,
    updateInterval,
    upload,
    download,
    total,
    expire,
    webPageUrl,
    supportUrl,
    populatedHeaders,
    userOverride,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileEntriesData &&
          other.id == this.id &&
          other.type == this.type &&
          other.active == this.active &&
          other.name == this.name &&
          other.url == this.url &&
          other.lastUpdate == this.lastUpdate &&
          other.updateInterval == this.updateInterval &&
          other.upload == this.upload &&
          other.download == this.download &&
          other.total == this.total &&
          other.expire == this.expire &&
          other.webPageUrl == this.webPageUrl &&
          other.supportUrl == this.supportUrl &&
          other.populatedHeaders == this.populatedHeaders &&
          other.userOverride == this.userOverride);
}

class ProfileEntriesCompanion extends UpdateCompanion<ProfileEntriesData> {
  final Value<String> id;
  final Value<String> type;
  final Value<bool> active;
  final Value<String> name;
  final Value<String?> url;
  final Value<DateTime> lastUpdate;
  final Value<int?> updateInterval;
  final Value<int?> upload;
  final Value<int?> download;
  final Value<int?> total;
  final Value<DateTime?> expire;
  final Value<String?> webPageUrl;
  final Value<String?> supportUrl;
  final Value<String?> populatedHeaders;
  final Value<String?> userOverride;
  final Value<int> rowid;
  const ProfileEntriesCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.active = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.lastUpdate = const Value.absent(),
    this.updateInterval = const Value.absent(),
    this.upload = const Value.absent(),
    this.download = const Value.absent(),
    this.total = const Value.absent(),
    this.expire = const Value.absent(),
    this.webPageUrl = const Value.absent(),
    this.supportUrl = const Value.absent(),
    this.populatedHeaders = const Value.absent(),
    this.userOverride = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfileEntriesCompanion.insert({
    required String id,
    required String type,
    required bool active,
    required String name,
    this.url = const Value.absent(),
    required DateTime lastUpdate,
    this.updateInterval = const Value.absent(),
    this.upload = const Value.absent(),
    this.download = const Value.absent(),
    this.total = const Value.absent(),
    this.expire = const Value.absent(),
    this.webPageUrl = const Value.absent(),
    this.supportUrl = const Value.absent(),
    this.populatedHeaders = const Value.absent(),
    this.userOverride = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       active = Value(active),
       name = Value(name),
       lastUpdate = Value(lastUpdate);
  static Insertable<ProfileEntriesData> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<bool>? active,
    Expression<String>? name,
    Expression<String>? url,
    Expression<DateTime>? lastUpdate,
    Expression<int>? updateInterval,
    Expression<int>? upload,
    Expression<int>? download,
    Expression<int>? total,
    Expression<DateTime>? expire,
    Expression<String>? webPageUrl,
    Expression<String>? supportUrl,
    Expression<String>? populatedHeaders,
    Expression<String>? userOverride,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (active != null) 'active': active,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (lastUpdate != null) 'last_update': lastUpdate,
      if (updateInterval != null) 'update_interval': updateInterval,
      if (upload != null) 'upload': upload,
      if (download != null) 'download': download,
      if (total != null) 'total': total,
      if (expire != null) 'expire': expire,
      if (webPageUrl != null) 'web_page_url': webPageUrl,
      if (supportUrl != null) 'support_url': supportUrl,
      if (populatedHeaders != null) 'populated_headers': populatedHeaders,
      if (userOverride != null) 'user_override': userOverride,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfileEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<bool>? active,
    Value<String>? name,
    Value<String?>? url,
    Value<DateTime>? lastUpdate,
    Value<int?>? updateInterval,
    Value<int?>? upload,
    Value<int?>? download,
    Value<int?>? total,
    Value<DateTime?>? expire,
    Value<String?>? webPageUrl,
    Value<String?>? supportUrl,
    Value<String?>? populatedHeaders,
    Value<String?>? userOverride,
    Value<int>? rowid,
  }) {
    return ProfileEntriesCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      active: active ?? this.active,
      name: name ?? this.name,
      url: url ?? this.url,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      updateInterval: updateInterval ?? this.updateInterval,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      total: total ?? this.total,
      expire: expire ?? this.expire,
      webPageUrl: webPageUrl ?? this.webPageUrl,
      supportUrl: supportUrl ?? this.supportUrl,
      populatedHeaders: populatedHeaders ?? this.populatedHeaders,
      userOverride: userOverride ?? this.userOverride,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (lastUpdate.present) {
      map['last_update'] = Variable<DateTime>(lastUpdate.value);
    }
    if (updateInterval.present) {
      map['update_interval'] = Variable<int>(updateInterval.value);
    }
    if (upload.present) {
      map['upload'] = Variable<int>(upload.value);
    }
    if (download.present) {
      map['download'] = Variable<int>(download.value);
    }
    if (total.present) {
      map['total'] = Variable<int>(total.value);
    }
    if (expire.present) {
      map['expire'] = Variable<DateTime>(expire.value);
    }
    if (webPageUrl.present) {
      map['web_page_url'] = Variable<String>(webPageUrl.value);
    }
    if (supportUrl.present) {
      map['support_url'] = Variable<String>(supportUrl.value);
    }
    if (populatedHeaders.present) {
      map['populated_headers'] = Variable<String>(populatedHeaders.value);
    }
    if (userOverride.present) {
      map['user_override'] = Variable<String>(userOverride.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileEntriesCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('active: $active, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('lastUpdate: $lastUpdate, ')
          ..write('updateInterval: $updateInterval, ')
          ..write('upload: $upload, ')
          ..write('download: $download, ')
          ..write('total: $total, ')
          ..write('expire: $expire, ')
          ..write('webPageUrl: $webPageUrl, ')
          ..write('supportUrl: $supportUrl, ')
          ..write('populatedHeaders: $populatedHeaders, ')
          ..write('userOverride: $userOverride, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class AppProxyEntries extends Table
    with TableInfo<AppProxyEntries, AppProxyEntriesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AppProxyEntries(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> pkgName = GeneratedColumn<String>(
    'pkg_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> flags = GeneratedColumn<int>(
    'flags',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [mode, pkgName, flags];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_proxy_entries';
  @override
  Set<GeneratedColumn> get $primaryKey => {mode, pkgName};
  @override
  AppProxyEntriesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppProxyEntriesData(
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      pkgName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pkg_name'],
      )!,
      flags: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flags'],
      )!,
    );
  }

  @override
  AppProxyEntries createAlias(String alias) {
    return AppProxyEntries(attachedDatabase, alias);
  }
}

class AppProxyEntriesData extends DataClass
    implements Insertable<AppProxyEntriesData> {
  final String mode;
  final String pkgName;
  final int flags;
  const AppProxyEntriesData({
    required this.mode,
    required this.pkgName,
    required this.flags,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mode'] = Variable<String>(mode);
    map['pkg_name'] = Variable<String>(pkgName);
    map['flags'] = Variable<int>(flags);
    return map;
  }

  AppProxyEntriesCompanion toCompanion(bool nullToAbsent) {
    return AppProxyEntriesCompanion(
      mode: Value(mode),
      pkgName: Value(pkgName),
      flags: Value(flags),
    );
  }

  factory AppProxyEntriesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppProxyEntriesData(
      mode: serializer.fromJson<String>(json['mode']),
      pkgName: serializer.fromJson<String>(json['pkgName']),
      flags: serializer.fromJson<int>(json['flags']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mode': serializer.toJson<String>(mode),
      'pkgName': serializer.toJson<String>(pkgName),
      'flags': serializer.toJson<int>(flags),
    };
  }

  AppProxyEntriesData copyWith({String? mode, String? pkgName, int? flags}) =>
      AppProxyEntriesData(
        mode: mode ?? this.mode,
        pkgName: pkgName ?? this.pkgName,
        flags: flags ?? this.flags,
      );
  AppProxyEntriesData copyWithCompanion(AppProxyEntriesCompanion data) {
    return AppProxyEntriesData(
      mode: data.mode.present ? data.mode.value : this.mode,
      pkgName: data.pkgName.present ? data.pkgName.value : this.pkgName,
      flags: data.flags.present ? data.flags.value : this.flags,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppProxyEntriesData(')
          ..write('mode: $mode, ')
          ..write('pkgName: $pkgName, ')
          ..write('flags: $flags')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mode, pkgName, flags);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppProxyEntriesData &&
          other.mode == this.mode &&
          other.pkgName == this.pkgName &&
          other.flags == this.flags);
}

class AppProxyEntriesCompanion extends UpdateCompanion<AppProxyEntriesData> {
  final Value<String> mode;
  final Value<String> pkgName;
  final Value<int> flags;
  final Value<int> rowid;
  const AppProxyEntriesCompanion({
    this.mode = const Value.absent(),
    this.pkgName = const Value.absent(),
    this.flags = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppProxyEntriesCompanion.insert({
    required String mode,
    required String pkgName,
    this.flags = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mode = Value(mode),
       pkgName = Value(pkgName);
  static Insertable<AppProxyEntriesData> custom({
    Expression<String>? mode,
    Expression<String>? pkgName,
    Expression<int>? flags,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mode != null) 'mode': mode,
      if (pkgName != null) 'pkg_name': pkgName,
      if (flags != null) 'flags': flags,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppProxyEntriesCompanion copyWith({
    Value<String>? mode,
    Value<String>? pkgName,
    Value<int>? flags,
    Value<int>? rowid,
  }) {
    return AppProxyEntriesCompanion(
      mode: mode ?? this.mode,
      pkgName: pkgName ?? this.pkgName,
      flags: flags ?? this.flags,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (pkgName.present) {
      map['pkg_name'] = Variable<String>(pkgName.value);
    }
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppProxyEntriesCompanion(')
          ..write('mode: $mode, ')
          ..write('pkgName: $pkgName, ')
          ..write('flags: $flags, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ProxyGroups extends Table with TableInfo<ProxyGroups, ProxyGroupsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ProxyGroups(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  late final GeneratedColumn<int> userOrder = GeneratedColumn<int>(
    'user_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<bool> ungrouped = GeneratedColumn<bool>(
    'ungrouped',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("ungrouped" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> subscription = GeneratedColumn<String>(
    'subscription',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> order = GeneratedColumn<String>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'origin\''),
  );
  late final GeneratedColumn<bool> isSelector = GeneratedColumn<bool>(
    'is_selector',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_selector" IN (0, 1))',
    ),
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> frontProxy = GeneratedColumn<int>(
    'front_proxy',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('-1'),
  );
  late final GeneratedColumn<int> landingProxy = GeneratedColumn<int>(
    'landing_proxy',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('-1'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userOrder,
    ungrouped,
    name,
    type,
    subscription,
    order,
    isSelector,
    frontProxy,
    landingProxy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'proxy_groups';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProxyGroupsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProxyGroupsData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      userOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_order'],
      )!,
      ungrouped: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ungrouped'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      subscription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subscription'],
      ),
      order: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order'],
      )!,
      isSelector: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_selector'],
      )!,
      frontProxy: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}front_proxy'],
      )!,
      landingProxy: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}landing_proxy'],
      )!,
    );
  }

  @override
  ProxyGroups createAlias(String alias) {
    return ProxyGroups(attachedDatabase, alias);
  }
}

class ProxyGroupsData extends DataClass implements Insertable<ProxyGroupsData> {
  final int id;
  final int userOrder;
  final bool ungrouped;
  final String? name;
  final String type;
  final String? subscription;
  final String order;
  final bool isSelector;
  final int frontProxy;
  final int landingProxy;
  const ProxyGroupsData({
    required this.id,
    required this.userOrder,
    required this.ungrouped,
    this.name,
    required this.type,
    this.subscription,
    required this.order,
    required this.isSelector,
    required this.frontProxy,
    required this.landingProxy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['user_order'] = Variable<int>(userOrder);
    map['ungrouped'] = Variable<bool>(ungrouped);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || subscription != null) {
      map['subscription'] = Variable<String>(subscription);
    }
    map['order'] = Variable<String>(order);
    map['is_selector'] = Variable<bool>(isSelector);
    map['front_proxy'] = Variable<int>(frontProxy);
    map['landing_proxy'] = Variable<int>(landingProxy);
    return map;
  }

  ProxyGroupsCompanion toCompanion(bool nullToAbsent) {
    return ProxyGroupsCompanion(
      id: Value(id),
      userOrder: Value(userOrder),
      ungrouped: Value(ungrouped),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      type: Value(type),
      subscription: subscription == null && nullToAbsent
          ? const Value.absent()
          : Value(subscription),
      order: Value(order),
      isSelector: Value(isSelector),
      frontProxy: Value(frontProxy),
      landingProxy: Value(landingProxy),
    );
  }

  factory ProxyGroupsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProxyGroupsData(
      id: serializer.fromJson<int>(json['id']),
      userOrder: serializer.fromJson<int>(json['userOrder']),
      ungrouped: serializer.fromJson<bool>(json['ungrouped']),
      name: serializer.fromJson<String?>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      subscription: serializer.fromJson<String?>(json['subscription']),
      order: serializer.fromJson<String>(json['order']),
      isSelector: serializer.fromJson<bool>(json['isSelector']),
      frontProxy: serializer.fromJson<int>(json['frontProxy']),
      landingProxy: serializer.fromJson<int>(json['landingProxy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'userOrder': serializer.toJson<int>(userOrder),
      'ungrouped': serializer.toJson<bool>(ungrouped),
      'name': serializer.toJson<String?>(name),
      'type': serializer.toJson<String>(type),
      'subscription': serializer.toJson<String?>(subscription),
      'order': serializer.toJson<String>(order),
      'isSelector': serializer.toJson<bool>(isSelector),
      'frontProxy': serializer.toJson<int>(frontProxy),
      'landingProxy': serializer.toJson<int>(landingProxy),
    };
  }

  ProxyGroupsData copyWith({
    int? id,
    int? userOrder,
    bool? ungrouped,
    Value<String?> name = const Value.absent(),
    String? type,
    Value<String?> subscription = const Value.absent(),
    String? order,
    bool? isSelector,
    int? frontProxy,
    int? landingProxy,
  }) => ProxyGroupsData(
    id: id ?? this.id,
    userOrder: userOrder ?? this.userOrder,
    ungrouped: ungrouped ?? this.ungrouped,
    name: name.present ? name.value : this.name,
    type: type ?? this.type,
    subscription: subscription.present ? subscription.value : this.subscription,
    order: order ?? this.order,
    isSelector: isSelector ?? this.isSelector,
    frontProxy: frontProxy ?? this.frontProxy,
    landingProxy: landingProxy ?? this.landingProxy,
  );
  ProxyGroupsData copyWithCompanion(ProxyGroupsCompanion data) {
    return ProxyGroupsData(
      id: data.id.present ? data.id.value : this.id,
      userOrder: data.userOrder.present ? data.userOrder.value : this.userOrder,
      ungrouped: data.ungrouped.present ? data.ungrouped.value : this.ungrouped,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      subscription: data.subscription.present
          ? data.subscription.value
          : this.subscription,
      order: data.order.present ? data.order.value : this.order,
      isSelector: data.isSelector.present
          ? data.isSelector.value
          : this.isSelector,
      frontProxy: data.frontProxy.present
          ? data.frontProxy.value
          : this.frontProxy,
      landingProxy: data.landingProxy.present
          ? data.landingProxy.value
          : this.landingProxy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProxyGroupsData(')
          ..write('id: $id, ')
          ..write('userOrder: $userOrder, ')
          ..write('ungrouped: $ungrouped, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('subscription: $subscription, ')
          ..write('order: $order, ')
          ..write('isSelector: $isSelector, ')
          ..write('frontProxy: $frontProxy, ')
          ..write('landingProxy: $landingProxy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userOrder,
    ungrouped,
    name,
    type,
    subscription,
    order,
    isSelector,
    frontProxy,
    landingProxy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProxyGroupsData &&
          other.id == this.id &&
          other.userOrder == this.userOrder &&
          other.ungrouped == this.ungrouped &&
          other.name == this.name &&
          other.type == this.type &&
          other.subscription == this.subscription &&
          other.order == this.order &&
          other.isSelector == this.isSelector &&
          other.frontProxy == this.frontProxy &&
          other.landingProxy == this.landingProxy);
}

class ProxyGroupsCompanion extends UpdateCompanion<ProxyGroupsData> {
  final Value<int> id;
  final Value<int> userOrder;
  final Value<bool> ungrouped;
  final Value<String?> name;
  final Value<String> type;
  final Value<String?> subscription;
  final Value<String> order;
  final Value<bool> isSelector;
  final Value<int> frontProxy;
  final Value<int> landingProxy;
  const ProxyGroupsCompanion({
    this.id = const Value.absent(),
    this.userOrder = const Value.absent(),
    this.ungrouped = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.subscription = const Value.absent(),
    this.order = const Value.absent(),
    this.isSelector = const Value.absent(),
    this.frontProxy = const Value.absent(),
    this.landingProxy = const Value.absent(),
  });
  ProxyGroupsCompanion.insert({
    this.id = const Value.absent(),
    this.userOrder = const Value.absent(),
    this.ungrouped = const Value.absent(),
    this.name = const Value.absent(),
    required String type,
    this.subscription = const Value.absent(),
    this.order = const Value.absent(),
    this.isSelector = const Value.absent(),
    this.frontProxy = const Value.absent(),
    this.landingProxy = const Value.absent(),
  }) : type = Value(type);
  static Insertable<ProxyGroupsData> custom({
    Expression<int>? id,
    Expression<int>? userOrder,
    Expression<bool>? ungrouped,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? subscription,
    Expression<String>? order,
    Expression<bool>? isSelector,
    Expression<int>? frontProxy,
    Expression<int>? landingProxy,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userOrder != null) 'user_order': userOrder,
      if (ungrouped != null) 'ungrouped': ungrouped,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (subscription != null) 'subscription': subscription,
      if (order != null) 'order': order,
      if (isSelector != null) 'is_selector': isSelector,
      if (frontProxy != null) 'front_proxy': frontProxy,
      if (landingProxy != null) 'landing_proxy': landingProxy,
    });
  }

  ProxyGroupsCompanion copyWith({
    Value<int>? id,
    Value<int>? userOrder,
    Value<bool>? ungrouped,
    Value<String?>? name,
    Value<String>? type,
    Value<String?>? subscription,
    Value<String>? order,
    Value<bool>? isSelector,
    Value<int>? frontProxy,
    Value<int>? landingProxy,
  }) {
    return ProxyGroupsCompanion(
      id: id ?? this.id,
      userOrder: userOrder ?? this.userOrder,
      ungrouped: ungrouped ?? this.ungrouped,
      name: name ?? this.name,
      type: type ?? this.type,
      subscription: subscription ?? this.subscription,
      order: order ?? this.order,
      isSelector: isSelector ?? this.isSelector,
      frontProxy: frontProxy ?? this.frontProxy,
      landingProxy: landingProxy ?? this.landingProxy,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (userOrder.present) {
      map['user_order'] = Variable<int>(userOrder.value);
    }
    if (ungrouped.present) {
      map['ungrouped'] = Variable<bool>(ungrouped.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (subscription.present) {
      map['subscription'] = Variable<String>(subscription.value);
    }
    if (order.present) {
      map['order'] = Variable<String>(order.value);
    }
    if (isSelector.present) {
      map['is_selector'] = Variable<bool>(isSelector.value);
    }
    if (frontProxy.present) {
      map['front_proxy'] = Variable<int>(frontProxy.value);
    }
    if (landingProxy.present) {
      map['landing_proxy'] = Variable<int>(landingProxy.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProxyGroupsCompanion(')
          ..write('id: $id, ')
          ..write('userOrder: $userOrder, ')
          ..write('ungrouped: $ungrouped, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('subscription: $subscription, ')
          ..write('order: $order, ')
          ..write('isSelector: $isSelector, ')
          ..write('frontProxy: $frontProxy, ')
          ..write('landingProxy: $landingProxy')
          ..write(')'))
        .toString();
  }
}

class ProxyEntities extends Table
    with TableInfo<ProxyEntities, ProxyEntitiesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ProxyEntities(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  late final GeneratedColumn<int> groupId = GeneratedColumn<int>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> userOrder = GeneratedColumn<int>(
    'user_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> tx = GeneratedColumn<int>(
    'tx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> rx = GeneratedColumn<int>(
    'rx',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<int> ping = GeneratedColumn<int>(
    'ping',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    groupId,
    tag,
    type,
    displayName,
    userOrder,
    tx,
    rx,
    status,
    ping,
    error,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'proxy_entities';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProxyEntitiesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProxyEntitiesData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_id'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      userOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_order'],
      )!,
      tx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tx'],
      )!,
      rx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rx'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      ping: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ping'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  ProxyEntities createAlias(String alias) {
    return ProxyEntities(attachedDatabase, alias);
  }
}

class ProxyEntitiesData extends DataClass
    implements Insertable<ProxyEntitiesData> {
  final int id;
  final int groupId;
  final String tag;
  final String type;
  final String displayName;
  final int userOrder;
  final int tx;
  final int rx;
  final int status;
  final int ping;
  final String? error;
  final String payload;
  const ProxyEntitiesData({
    required this.id,
    required this.groupId,
    required this.tag,
    required this.type,
    required this.displayName,
    required this.userOrder,
    required this.tx,
    required this.rx,
    required this.status,
    required this.ping,
    this.error,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['group_id'] = Variable<int>(groupId);
    map['tag'] = Variable<String>(tag);
    map['type'] = Variable<String>(type);
    map['display_name'] = Variable<String>(displayName);
    map['user_order'] = Variable<int>(userOrder);
    map['tx'] = Variable<int>(tx);
    map['rx'] = Variable<int>(rx);
    map['status'] = Variable<int>(status);
    map['ping'] = Variable<int>(ping);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['payload'] = Variable<String>(payload);
    return map;
  }

  ProxyEntitiesCompanion toCompanion(bool nullToAbsent) {
    return ProxyEntitiesCompanion(
      id: Value(id),
      groupId: Value(groupId),
      tag: Value(tag),
      type: Value(type),
      displayName: Value(displayName),
      userOrder: Value(userOrder),
      tx: Value(tx),
      rx: Value(rx),
      status: Value(status),
      ping: Value(ping),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      payload: Value(payload),
    );
  }

  factory ProxyEntitiesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProxyEntitiesData(
      id: serializer.fromJson<int>(json['id']),
      groupId: serializer.fromJson<int>(json['groupId']),
      tag: serializer.fromJson<String>(json['tag']),
      type: serializer.fromJson<String>(json['type']),
      displayName: serializer.fromJson<String>(json['displayName']),
      userOrder: serializer.fromJson<int>(json['userOrder']),
      tx: serializer.fromJson<int>(json['tx']),
      rx: serializer.fromJson<int>(json['rx']),
      status: serializer.fromJson<int>(json['status']),
      ping: serializer.fromJson<int>(json['ping']),
      error: serializer.fromJson<String?>(json['error']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'groupId': serializer.toJson<int>(groupId),
      'tag': serializer.toJson<String>(tag),
      'type': serializer.toJson<String>(type),
      'displayName': serializer.toJson<String>(displayName),
      'userOrder': serializer.toJson<int>(userOrder),
      'tx': serializer.toJson<int>(tx),
      'rx': serializer.toJson<int>(rx),
      'status': serializer.toJson<int>(status),
      'ping': serializer.toJson<int>(ping),
      'error': serializer.toJson<String?>(error),
      'payload': serializer.toJson<String>(payload),
    };
  }

  ProxyEntitiesData copyWith({
    int? id,
    int? groupId,
    String? tag,
    String? type,
    String? displayName,
    int? userOrder,
    int? tx,
    int? rx,
    int? status,
    int? ping,
    Value<String?> error = const Value.absent(),
    String? payload,
  }) => ProxyEntitiesData(
    id: id ?? this.id,
    groupId: groupId ?? this.groupId,
    tag: tag ?? this.tag,
    type: type ?? this.type,
    displayName: displayName ?? this.displayName,
    userOrder: userOrder ?? this.userOrder,
    tx: tx ?? this.tx,
    rx: rx ?? this.rx,
    status: status ?? this.status,
    ping: ping ?? this.ping,
    error: error.present ? error.value : this.error,
    payload: payload ?? this.payload,
  );
  ProxyEntitiesData copyWithCompanion(ProxyEntitiesCompanion data) {
    return ProxyEntitiesData(
      id: data.id.present ? data.id.value : this.id,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      tag: data.tag.present ? data.tag.value : this.tag,
      type: data.type.present ? data.type.value : this.type,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      userOrder: data.userOrder.present ? data.userOrder.value : this.userOrder,
      tx: data.tx.present ? data.tx.value : this.tx,
      rx: data.rx.present ? data.rx.value : this.rx,
      status: data.status.present ? data.status.value : this.status,
      ping: data.ping.present ? data.ping.value : this.ping,
      error: data.error.present ? data.error.value : this.error,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProxyEntitiesData(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('tag: $tag, ')
          ..write('type: $type, ')
          ..write('displayName: $displayName, ')
          ..write('userOrder: $userOrder, ')
          ..write('tx: $tx, ')
          ..write('rx: $rx, ')
          ..write('status: $status, ')
          ..write('ping: $ping, ')
          ..write('error: $error, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    groupId,
    tag,
    type,
    displayName,
    userOrder,
    tx,
    rx,
    status,
    ping,
    error,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProxyEntitiesData &&
          other.id == this.id &&
          other.groupId == this.groupId &&
          other.tag == this.tag &&
          other.type == this.type &&
          other.displayName == this.displayName &&
          other.userOrder == this.userOrder &&
          other.tx == this.tx &&
          other.rx == this.rx &&
          other.status == this.status &&
          other.ping == this.ping &&
          other.error == this.error &&
          other.payload == this.payload);
}

class ProxyEntitiesCompanion extends UpdateCompanion<ProxyEntitiesData> {
  final Value<int> id;
  final Value<int> groupId;
  final Value<String> tag;
  final Value<String> type;
  final Value<String> displayName;
  final Value<int> userOrder;
  final Value<int> tx;
  final Value<int> rx;
  final Value<int> status;
  final Value<int> ping;
  final Value<String?> error;
  final Value<String> payload;
  const ProxyEntitiesCompanion({
    this.id = const Value.absent(),
    this.groupId = const Value.absent(),
    this.tag = const Value.absent(),
    this.type = const Value.absent(),
    this.displayName = const Value.absent(),
    this.userOrder = const Value.absent(),
    this.tx = const Value.absent(),
    this.rx = const Value.absent(),
    this.status = const Value.absent(),
    this.ping = const Value.absent(),
    this.error = const Value.absent(),
    this.payload = const Value.absent(),
  });
  ProxyEntitiesCompanion.insert({
    this.id = const Value.absent(),
    required int groupId,
    required String tag,
    required String type,
    required String displayName,
    this.userOrder = const Value.absent(),
    this.tx = const Value.absent(),
    this.rx = const Value.absent(),
    this.status = const Value.absent(),
    this.ping = const Value.absent(),
    this.error = const Value.absent(),
    required String payload,
  }) : groupId = Value(groupId),
       tag = Value(tag),
       type = Value(type),
       displayName = Value(displayName),
       payload = Value(payload);
  static Insertable<ProxyEntitiesData> custom({
    Expression<int>? id,
    Expression<int>? groupId,
    Expression<String>? tag,
    Expression<String>? type,
    Expression<String>? displayName,
    Expression<int>? userOrder,
    Expression<int>? tx,
    Expression<int>? rx,
    Expression<int>? status,
    Expression<int>? ping,
    Expression<String>? error,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupId != null) 'group_id': groupId,
      if (tag != null) 'tag': tag,
      if (type != null) 'type': type,
      if (displayName != null) 'display_name': displayName,
      if (userOrder != null) 'user_order': userOrder,
      if (tx != null) 'tx': tx,
      if (rx != null) 'rx': rx,
      if (status != null) 'status': status,
      if (ping != null) 'ping': ping,
      if (error != null) 'error': error,
      if (payload != null) 'payload': payload,
    });
  }

  ProxyEntitiesCompanion copyWith({
    Value<int>? id,
    Value<int>? groupId,
    Value<String>? tag,
    Value<String>? type,
    Value<String>? displayName,
    Value<int>? userOrder,
    Value<int>? tx,
    Value<int>? rx,
    Value<int>? status,
    Value<int>? ping,
    Value<String?>? error,
    Value<String>? payload,
  }) {
    return ProxyEntitiesCompanion(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      tag: tag ?? this.tag,
      type: type ?? this.type,
      displayName: displayName ?? this.displayName,
      userOrder: userOrder ?? this.userOrder,
      tx: tx ?? this.tx,
      rx: rx ?? this.rx,
      status: status ?? this.status,
      ping: ping ?? this.ping,
      error: error ?? this.error,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<int>(groupId.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (userOrder.present) {
      map['user_order'] = Variable<int>(userOrder.value);
    }
    if (tx.present) {
      map['tx'] = Variable<int>(tx.value);
    }
    if (rx.present) {
      map['rx'] = Variable<int>(rx.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (ping.present) {
      map['ping'] = Variable<int>(ping.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProxyEntitiesCompanion(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('tag: $tag, ')
          ..write('type: $type, ')
          ..write('displayName: $displayName, ')
          ..write('userOrder: $userOrder, ')
          ..write('tx: $tx, ')
          ..write('rx: $rx, ')
          ..write('status: $status, ')
          ..write('ping: $ping, ')
          ..write('error: $error, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV7 extends GeneratedDatabase {
  DatabaseAtV7(QueryExecutor e) : super(e);
  late final ProfileEntries profileEntries = ProfileEntries(this);
  late final AppProxyEntries appProxyEntries = AppProxyEntries(this);
  late final ProxyGroups proxyGroups = ProxyGroups(this);
  late final ProxyEntities proxyEntities = ProxyEntities(this);
  late final Index proxyEntitiesGroupId = Index(
    'proxy_entities_group_id',
    'CREATE INDEX proxy_entities_group_id ON proxy_entities (group_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profileEntries,
    appProxyEntries,
    proxyGroups,
    proxyEntities,
    proxyEntitiesGroupId,
  ];
  @override
  int get schemaVersion => 7;
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}
