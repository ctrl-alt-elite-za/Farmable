// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, displayName, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final String id;

  /// LOCAL-ONLY. The server's `users` table carries no name — auth is not
  /// built yet (#9). Home opens with "Hello, Sipho", and a greeting is the
  /// one place the product cannot be anonymous.
  final String displayName;
  final DateTime createdAt;
  const User({
    required this.id,
    required this.displayName,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      displayName: Value(displayName),
      createdAt: Value(createdAt),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  User copyWith({String? id, String? displayName, DateTime? createdAt}) => User(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    createdAt: createdAt ?? this.createdAt,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, displayName, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.createdAt == this.createdAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String id,
    required String displayName,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       createdAt = Value(createdAt);
  static Insertable<User> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FarmsTable extends Farms with TableInfo<$FarmsTable, Farm> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FarmsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localityMeta = const VerificationMeta(
    'locality',
  );
  @override
  late final GeneratedColumn<String> locality = GeneratedColumn<String>(
    'locality',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    name,
    locality,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'farms';
  @override
  VerificationContext validateIntegrity(
    Insertable<Farm> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('locality')) {
      context.handle(
        _localityMeta,
        locality.isAcceptableOrUnknown(data['locality']!, _localityMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Farm map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Farm(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      locality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locality'],
      ),
    );
  }

  @override
  $FarmsTable createAlias(String alias) {
    return $FarmsTable(attachedDatabase, alias);
  }
}

class Farm extends DataClass implements Insertable<Farm> {
  final String id;
  final String farmId;
  final String ownerId;
  final int version;
  final String syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String name;

  /// LOCAL-ONLY. "KwaMashu, KwaZulu-Natal". `farms` has no place column.
  final String? locality;
  const Farm({
    required this.id,
    required this.farmId,
    required this.ownerId,
    required this.version,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.name,
    this.locality,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || locality != null) {
      map['locality'] = Variable<String>(locality);
    }
    return map;
  }

  FarmsCompanion toCompanion(bool nullToAbsent) {
    return FarmsCompanion(
      id: Value(id),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      version: Value(version),
      syncState: Value(syncState),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      name: Value(name),
      locality: locality == null && nullToAbsent
          ? const Value.absent()
          : Value(locality),
    );
  }

  factory Farm.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Farm(
      id: serializer.fromJson<String>(json['id']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      name: serializer.fromJson<String>(json['name']),
      locality: serializer.fromJson<String?>(json['locality']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'name': serializer.toJson<String>(name),
      'locality': serializer.toJson<String?>(locality),
    };
  }

  Farm copyWith({
    String? id,
    String? farmId,
    String? ownerId,
    int? version,
    String? syncState,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? name,
    Value<String?> locality = const Value.absent(),
  }) => Farm(
    id: id ?? this.id,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    name: name ?? this.name,
    locality: locality.present ? locality.value : this.locality,
  );
  Farm copyWithCompanion(FarmsCompanion data) {
    return Farm(
      id: data.id.present ? data.id.value : this.id,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      name: data.name.present ? data.name.value : this.name,
      locality: data.locality.present ? data.locality.value : this.locality,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Farm(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('name: $name, ')
          ..write('locality: $locality')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    name,
    locality,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Farm &&
          other.id == this.id &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.version == this.version &&
          other.syncState == this.syncState &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.name == this.name &&
          other.locality == this.locality);
}

class FarmsCompanion extends UpdateCompanion<Farm> {
  final Value<String> id;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<int> version;
  final Value<String> syncState;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> name;
  final Value<String?> locality;
  final Value<int> rowid;
  const FarmsCompanion({
    this.id = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.name = const Value.absent(),
    this.locality = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FarmsCompanion.insert({
    required String id,
    required String farmId,
    required String ownerId,
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String name,
    this.locality = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       name = Value(name);
  static Insertable<Farm> custom({
    Expression<String>? id,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<int>? version,
    Expression<String>? syncState,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? name,
    Expression<String>? locality,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (name != null) 'name': name,
      if (locality != null) 'locality': locality,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FarmsCompanion copyWith({
    Value<String>? id,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<int>? version,
    Value<String>? syncState,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? name,
    Value<String?>? locality,
    Value<int>? rowid,
  }) {
    return FarmsCompanion(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      name: name ?? this.name,
      locality: locality ?? this.locality,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (locality.present) {
      map['locality'] = Variable<String>(locality.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FarmsCompanion(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('name: $name, ')
          ..write('locality: $locality, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SectionsTable extends Sections with TableInfo<$SectionsTable, Section> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boundaryMeta = const VerificationMeta(
    'boundary',
  );
  @override
  late final GeneratedColumn<String> boundary = GeneratedColumn<String>(
    'boundary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _areaM2Meta = const VerificationMeta('areaM2');
  @override
  late final GeneratedColumn<String> areaM2 = GeneratedColumn<String>(
    'area_m2',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _areaSourceMeta = const VerificationMeta(
    'areaSource',
  );
  @override
  late final GeneratedColumn<String> areaSource = GeneratedColumn<String>(
    'area_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    name,
    boundary,
    areaM2,
    areaSource,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Section> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('boundary')) {
      context.handle(
        _boundaryMeta,
        boundary.isAcceptableOrUnknown(data['boundary']!, _boundaryMeta),
      );
    }
    if (data.containsKey('area_m2')) {
      context.handle(
        _areaM2Meta,
        areaM2.isAcceptableOrUnknown(data['area_m2']!, _areaM2Meta),
      );
    }
    if (data.containsKey('area_source')) {
      context.handle(
        _areaSourceMeta,
        areaSource.isAcceptableOrUnknown(data['area_source']!, _areaSourceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Section map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Section(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      boundary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}boundary'],
      ),
      areaM2: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_m2'],
      ),
      areaSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_source'],
      ),
    );
  }

  @override
  $SectionsTable createAlias(String alias) {
    return $SectionsTable(attachedDatabase, alias);
  }
}

class Section extends DataClass implements Insertable<Section> {
  final String id;
  final String farmId;
  final String ownerId;
  final int version;
  final String syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String name;

  /// GeoJSON, as the server stores it (`JSON` / `JSONB`). Held as text
  /// because nothing on these two screens reads the geometry — the map
  /// preview draws from it, and parsing happens there, once.
  final String? boundary;

  /// `Numeric(14, 2)` on the server. See the library comment.
  final String? areaM2;

  /// How the area was arrived at — `demo_api`'s `area_source`. The production
  /// `sections` table has no such column yet; the design surfaces it because
  /// a farmer-supplied number and a walked boundary deserve different
  /// confidence.
  final String? areaSource;
  const Section({
    required this.id,
    required this.farmId,
    required this.ownerId,
    required this.version,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.name,
    this.boundary,
    this.areaM2,
    this.areaSource,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || boundary != null) {
      map['boundary'] = Variable<String>(boundary);
    }
    if (!nullToAbsent || areaM2 != null) {
      map['area_m2'] = Variable<String>(areaM2);
    }
    if (!nullToAbsent || areaSource != null) {
      map['area_source'] = Variable<String>(areaSource);
    }
    return map;
  }

  SectionsCompanion toCompanion(bool nullToAbsent) {
    return SectionsCompanion(
      id: Value(id),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      version: Value(version),
      syncState: Value(syncState),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      name: Value(name),
      boundary: boundary == null && nullToAbsent
          ? const Value.absent()
          : Value(boundary),
      areaM2: areaM2 == null && nullToAbsent
          ? const Value.absent()
          : Value(areaM2),
      areaSource: areaSource == null && nullToAbsent
          ? const Value.absent()
          : Value(areaSource),
    );
  }

  factory Section.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Section(
      id: serializer.fromJson<String>(json['id']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      name: serializer.fromJson<String>(json['name']),
      boundary: serializer.fromJson<String?>(json['boundary']),
      areaM2: serializer.fromJson<String?>(json['areaM2']),
      areaSource: serializer.fromJson<String?>(json['areaSource']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'name': serializer.toJson<String>(name),
      'boundary': serializer.toJson<String?>(boundary),
      'areaM2': serializer.toJson<String?>(areaM2),
      'areaSource': serializer.toJson<String?>(areaSource),
    };
  }

  Section copyWith({
    String? id,
    String? farmId,
    String? ownerId,
    int? version,
    String? syncState,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? name,
    Value<String?> boundary = const Value.absent(),
    Value<String?> areaM2 = const Value.absent(),
    Value<String?> areaSource = const Value.absent(),
  }) => Section(
    id: id ?? this.id,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    name: name ?? this.name,
    boundary: boundary.present ? boundary.value : this.boundary,
    areaM2: areaM2.present ? areaM2.value : this.areaM2,
    areaSource: areaSource.present ? areaSource.value : this.areaSource,
  );
  Section copyWithCompanion(SectionsCompanion data) {
    return Section(
      id: data.id.present ? data.id.value : this.id,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      name: data.name.present ? data.name.value : this.name,
      boundary: data.boundary.present ? data.boundary.value : this.boundary,
      areaM2: data.areaM2.present ? data.areaM2.value : this.areaM2,
      areaSource: data.areaSource.present
          ? data.areaSource.value
          : this.areaSource,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Section(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('name: $name, ')
          ..write('boundary: $boundary, ')
          ..write('areaM2: $areaM2, ')
          ..write('areaSource: $areaSource')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    name,
    boundary,
    areaM2,
    areaSource,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Section &&
          other.id == this.id &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.version == this.version &&
          other.syncState == this.syncState &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.name == this.name &&
          other.boundary == this.boundary &&
          other.areaM2 == this.areaM2 &&
          other.areaSource == this.areaSource);
}

class SectionsCompanion extends UpdateCompanion<Section> {
  final Value<String> id;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<int> version;
  final Value<String> syncState;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> name;
  final Value<String?> boundary;
  final Value<String?> areaM2;
  final Value<String?> areaSource;
  final Value<int> rowid;
  const SectionsCompanion({
    this.id = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.name = const Value.absent(),
    this.boundary = const Value.absent(),
    this.areaM2 = const Value.absent(),
    this.areaSource = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SectionsCompanion.insert({
    required String id,
    required String farmId,
    required String ownerId,
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String name,
    this.boundary = const Value.absent(),
    this.areaM2 = const Value.absent(),
    this.areaSource = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       name = Value(name);
  static Insertable<Section> custom({
    Expression<String>? id,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<int>? version,
    Expression<String>? syncState,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? name,
    Expression<String>? boundary,
    Expression<String>? areaM2,
    Expression<String>? areaSource,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (name != null) 'name': name,
      if (boundary != null) 'boundary': boundary,
      if (areaM2 != null) 'area_m2': areaM2,
      if (areaSource != null) 'area_source': areaSource,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<int>? version,
    Value<String>? syncState,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? name,
    Value<String?>? boundary,
    Value<String?>? areaM2,
    Value<String?>? areaSource,
    Value<int>? rowid,
  }) {
    return SectionsCompanion(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      name: name ?? this.name,
      boundary: boundary ?? this.boundary,
      areaM2: areaM2 ?? this.areaM2,
      areaSource: areaSource ?? this.areaSource,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (boundary.present) {
      map['boundary'] = Variable<String>(boundary.value);
    }
    if (areaM2.present) {
      map['area_m2'] = Variable<String>(areaM2.value);
    }
    if (areaSource.present) {
      map['area_source'] = Variable<String>(areaSource.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SectionsCompanion(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('name: $name, ')
          ..write('boundary: $boundary, ')
          ..write('areaM2: $areaM2, ')
          ..write('areaSource: $areaSource, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlantingsTable extends Plantings
    with TableInfo<$PlantingsTable, Planting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlantingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cropMeta = const VerificationMeta('crop');
  @override
  late final GeneratedColumn<String> crop = GeneratedColumn<String>(
    'crop',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _varietyMeta = const VerificationMeta(
    'variety',
  );
  @override
  late final GeneratedColumn<String> variety = GeneratedColumn<String>(
    'variety',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plantedOnMeta = const VerificationMeta(
    'plantedOn',
  );
  @override
  late final GeneratedColumn<DateTime> plantedOn = GeneratedColumn<DateTime>(
    'planted_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCurrentMeta = const VerificationMeta(
    'isCurrent',
  );
  @override
  late final GeneratedColumn<bool> isCurrent = GeneratedColumn<bool>(
    'is_current',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_current" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    crop,
    variety,
    plantedOn,
    isCurrent,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plantings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Planting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('crop')) {
      context.handle(
        _cropMeta,
        crop.isAcceptableOrUnknown(data['crop']!, _cropMeta),
      );
    } else if (isInserting) {
      context.missing(_cropMeta);
    }
    if (data.containsKey('variety')) {
      context.handle(
        _varietyMeta,
        variety.isAcceptableOrUnknown(data['variety']!, _varietyMeta),
      );
    }
    if (data.containsKey('planted_on')) {
      context.handle(
        _plantedOnMeta,
        plantedOn.isAcceptableOrUnknown(data['planted_on']!, _plantedOnMeta),
      );
    }
    if (data.containsKey('is_current')) {
      context.handle(
        _isCurrentMeta,
        isCurrent.isAcceptableOrUnknown(data['is_current']!, _isCurrentMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Planting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Planting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      crop: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop'],
      )!,
      variety: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variety'],
      ),
      plantedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}planted_on'],
      ),
      isCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_current'],
      )!,
    );
  }

  @override
  $PlantingsTable createAlias(String alias) {
    return $PlantingsTable(attachedDatabase, alias);
  }
}

class Planting extends DataClass implements Insertable<Planting> {
  final String id;
  final String farmId;
  final String ownerId;
  final int version;
  final String syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String sectionId;

  /// Free text on the server, so free text here. The `demo_api` `Crop` enum
  /// is cabbage and spinach only and cannot hold the demo's Tomato Section.
  final String crop;

  /// LOCAL-ONLY. "Star 3306" — the design names the cultivar.
  final String? variety;
  final DateTime? plantedOn;
  final bool isCurrent;
  const Planting({
    required this.id,
    required this.farmId,
    required this.ownerId,
    required this.version,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.sectionId,
    required this.crop,
    this.variety,
    this.plantedOn,
    required this.isCurrent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['section_id'] = Variable<String>(sectionId);
    map['crop'] = Variable<String>(crop);
    if (!nullToAbsent || variety != null) {
      map['variety'] = Variable<String>(variety);
    }
    if (!nullToAbsent || plantedOn != null) {
      map['planted_on'] = Variable<DateTime>(plantedOn);
    }
    map['is_current'] = Variable<bool>(isCurrent);
    return map;
  }

  PlantingsCompanion toCompanion(bool nullToAbsent) {
    return PlantingsCompanion(
      id: Value(id),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      version: Value(version),
      syncState: Value(syncState),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      sectionId: Value(sectionId),
      crop: Value(crop),
      variety: variety == null && nullToAbsent
          ? const Value.absent()
          : Value(variety),
      plantedOn: plantedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(plantedOn),
      isCurrent: Value(isCurrent),
    );
  }

  factory Planting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Planting(
      id: serializer.fromJson<String>(json['id']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      crop: serializer.fromJson<String>(json['crop']),
      variety: serializer.fromJson<String?>(json['variety']),
      plantedOn: serializer.fromJson<DateTime?>(json['plantedOn']),
      isCurrent: serializer.fromJson<bool>(json['isCurrent']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'sectionId': serializer.toJson<String>(sectionId),
      'crop': serializer.toJson<String>(crop),
      'variety': serializer.toJson<String?>(variety),
      'plantedOn': serializer.toJson<DateTime?>(plantedOn),
      'isCurrent': serializer.toJson<bool>(isCurrent),
    };
  }

  Planting copyWith({
    String? id,
    String? farmId,
    String? ownerId,
    int? version,
    String? syncState,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? sectionId,
    String? crop,
    Value<String?> variety = const Value.absent(),
    Value<DateTime?> plantedOn = const Value.absent(),
    bool? isCurrent,
  }) => Planting(
    id: id ?? this.id,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    sectionId: sectionId ?? this.sectionId,
    crop: crop ?? this.crop,
    variety: variety.present ? variety.value : this.variety,
    plantedOn: plantedOn.present ? plantedOn.value : this.plantedOn,
    isCurrent: isCurrent ?? this.isCurrent,
  );
  Planting copyWithCompanion(PlantingsCompanion data) {
    return Planting(
      id: data.id.present ? data.id.value : this.id,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      crop: data.crop.present ? data.crop.value : this.crop,
      variety: data.variety.present ? data.variety.value : this.variety,
      plantedOn: data.plantedOn.present ? data.plantedOn.value : this.plantedOn,
      isCurrent: data.isCurrent.present ? data.isCurrent.value : this.isCurrent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Planting(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('crop: $crop, ')
          ..write('variety: $variety, ')
          ..write('plantedOn: $plantedOn, ')
          ..write('isCurrent: $isCurrent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    crop,
    variety,
    plantedOn,
    isCurrent,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Planting &&
          other.id == this.id &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.version == this.version &&
          other.syncState == this.syncState &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.sectionId == this.sectionId &&
          other.crop == this.crop &&
          other.variety == this.variety &&
          other.plantedOn == this.plantedOn &&
          other.isCurrent == this.isCurrent);
}

class PlantingsCompanion extends UpdateCompanion<Planting> {
  final Value<String> id;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<int> version;
  final Value<String> syncState;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> sectionId;
  final Value<String> crop;
  final Value<String?> variety;
  final Value<DateTime?> plantedOn;
  final Value<bool> isCurrent;
  final Value<int> rowid;
  const PlantingsCompanion({
    this.id = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.crop = const Value.absent(),
    this.variety = const Value.absent(),
    this.plantedOn = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlantingsCompanion.insert({
    required String id,
    required String farmId,
    required String ownerId,
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String sectionId,
    required String crop,
    this.variety = const Value.absent(),
    this.plantedOn = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       sectionId = Value(sectionId),
       crop = Value(crop);
  static Insertable<Planting> custom({
    Expression<String>? id,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<int>? version,
    Expression<String>? syncState,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? sectionId,
    Expression<String>? crop,
    Expression<String>? variety,
    Expression<DateTime>? plantedOn,
    Expression<bool>? isCurrent,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (sectionId != null) 'section_id': sectionId,
      if (crop != null) 'crop': crop,
      if (variety != null) 'variety': variety,
      if (plantedOn != null) 'planted_on': plantedOn,
      if (isCurrent != null) 'is_current': isCurrent,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlantingsCompanion copyWith({
    Value<String>? id,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<int>? version,
    Value<String>? syncState,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? sectionId,
    Value<String>? crop,
    Value<String?>? variety,
    Value<DateTime?>? plantedOn,
    Value<bool>? isCurrent,
    Value<int>? rowid,
  }) {
    return PlantingsCompanion(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      sectionId: sectionId ?? this.sectionId,
      crop: crop ?? this.crop,
      variety: variety ?? this.variety,
      plantedOn: plantedOn ?? this.plantedOn,
      isCurrent: isCurrent ?? this.isCurrent,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (crop.present) {
      map['crop'] = Variable<String>(crop.value);
    }
    if (variety.present) {
      map['variety'] = Variable<String>(variety.value);
    }
    if (plantedOn.present) {
      map['planted_on'] = Variable<DateTime>(plantedOn.value);
    }
    if (isCurrent.present) {
      map['is_current'] = Variable<bool>(isCurrent.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlantingsCompanion(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('crop: $crop, ')
          ..write('variety: $variety, ')
          ..write('plantedOn: $plantedOn, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObservationsTable extends Observations
    with TableInfo<$ObservationsTable, Observation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _healthStatusMeta = const VerificationMeta(
    'healthStatus',
  );
  @override
  late final GeneratedColumn<String> healthStatus = GeneratedColumn<String>(
    'health_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actionTakenMeta = const VerificationMeta(
    'actionTaken',
  );
  @override
  late final GeneratedColumn<String> actionTaken = GeneratedColumn<String>(
    'action_taken',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localMediaIdMeta = const VerificationMeta(
    'localMediaId',
  );
  @override
  late final GeneratedColumn<String> localMediaId = GeneratedColumn<String>(
    'local_media_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByVoiceMeta = const VerificationMeta(
    'createdByVoice',
  );
  @override
  late final GeneratedColumn<bool> createdByVoice = GeneratedColumn<bool>(
    'created_by_voice',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("created_by_voice" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _healthScoreMeta = const VerificationMeta(
    'healthScore',
  );
  @override
  late final GeneratedColumn<int> healthScore = GeneratedColumn<int>(
    'health_score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    type,
    note,
    healthStatus,
    actionTaken,
    localMediaId,
    createdByVoice,
    healthScore,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Observation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('health_status')) {
      context.handle(
        _healthStatusMeta,
        healthStatus.isAcceptableOrUnknown(
          data['health_status']!,
          _healthStatusMeta,
        ),
      );
    }
    if (data.containsKey('action_taken')) {
      context.handle(
        _actionTakenMeta,
        actionTaken.isAcceptableOrUnknown(
          data['action_taken']!,
          _actionTakenMeta,
        ),
      );
    }
    if (data.containsKey('local_media_id')) {
      context.handle(
        _localMediaIdMeta,
        localMediaId.isAcceptableOrUnknown(
          data['local_media_id']!,
          _localMediaIdMeta,
        ),
      );
    }
    if (data.containsKey('created_by_voice')) {
      context.handle(
        _createdByVoiceMeta,
        createdByVoice.isAcceptableOrUnknown(
          data['created_by_voice']!,
          _createdByVoiceMeta,
        ),
      );
    }
    if (data.containsKey('health_score')) {
      context.handle(
        _healthScoreMeta,
        healthScore.isAcceptableOrUnknown(
          data['health_score']!,
          _healthScoreMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Observation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Observation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      healthStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health_status'],
      ),
      actionTaken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_taken'],
      ),
      localMediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_media_id'],
      ),
      createdByVoice: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}created_by_voice'],
      )!,
      healthScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}health_score'],
      ),
    );
  }

  @override
  $ObservationsTable createAlias(String alias) {
    return $ObservationsTable(attachedDatabase, alias);
  }
}

class Observation extends DataClass implements Insertable<Observation> {
  final String id;
  final String farmId;
  final String ownerId;
  final int version;
  final String syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String sectionId;
  final String type;
  final String note;
  final String? healthStatus;
  final String? actionTaken;
  final String? localMediaId;
  final bool createdByVoice;

  /// LOCAL-ONLY. The gauge is a number out of 100; `health_status` is a word.
  final int? healthScore;
  const Observation({
    required this.id,
    required this.farmId,
    required this.ownerId,
    required this.version,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.sectionId,
    required this.type,
    required this.note,
    this.healthStatus,
    this.actionTaken,
    this.localMediaId,
    required this.createdByVoice,
    this.healthScore,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['section_id'] = Variable<String>(sectionId);
    map['type'] = Variable<String>(type);
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || healthStatus != null) {
      map['health_status'] = Variable<String>(healthStatus);
    }
    if (!nullToAbsent || actionTaken != null) {
      map['action_taken'] = Variable<String>(actionTaken);
    }
    if (!nullToAbsent || localMediaId != null) {
      map['local_media_id'] = Variable<String>(localMediaId);
    }
    map['created_by_voice'] = Variable<bool>(createdByVoice);
    if (!nullToAbsent || healthScore != null) {
      map['health_score'] = Variable<int>(healthScore);
    }
    return map;
  }

  ObservationsCompanion toCompanion(bool nullToAbsent) {
    return ObservationsCompanion(
      id: Value(id),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      version: Value(version),
      syncState: Value(syncState),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      sectionId: Value(sectionId),
      type: Value(type),
      note: Value(note),
      healthStatus: healthStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(healthStatus),
      actionTaken: actionTaken == null && nullToAbsent
          ? const Value.absent()
          : Value(actionTaken),
      localMediaId: localMediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(localMediaId),
      createdByVoice: Value(createdByVoice),
      healthScore: healthScore == null && nullToAbsent
          ? const Value.absent()
          : Value(healthScore),
    );
  }

  factory Observation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Observation(
      id: serializer.fromJson<String>(json['id']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      type: serializer.fromJson<String>(json['type']),
      note: serializer.fromJson<String>(json['note']),
      healthStatus: serializer.fromJson<String?>(json['healthStatus']),
      actionTaken: serializer.fromJson<String?>(json['actionTaken']),
      localMediaId: serializer.fromJson<String?>(json['localMediaId']),
      createdByVoice: serializer.fromJson<bool>(json['createdByVoice']),
      healthScore: serializer.fromJson<int?>(json['healthScore']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'sectionId': serializer.toJson<String>(sectionId),
      'type': serializer.toJson<String>(type),
      'note': serializer.toJson<String>(note),
      'healthStatus': serializer.toJson<String?>(healthStatus),
      'actionTaken': serializer.toJson<String?>(actionTaken),
      'localMediaId': serializer.toJson<String?>(localMediaId),
      'createdByVoice': serializer.toJson<bool>(createdByVoice),
      'healthScore': serializer.toJson<int?>(healthScore),
    };
  }

  Observation copyWith({
    String? id,
    String? farmId,
    String? ownerId,
    int? version,
    String? syncState,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? sectionId,
    String? type,
    String? note,
    Value<String?> healthStatus = const Value.absent(),
    Value<String?> actionTaken = const Value.absent(),
    Value<String?> localMediaId = const Value.absent(),
    bool? createdByVoice,
    Value<int?> healthScore = const Value.absent(),
  }) => Observation(
    id: id ?? this.id,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    sectionId: sectionId ?? this.sectionId,
    type: type ?? this.type,
    note: note ?? this.note,
    healthStatus: healthStatus.present ? healthStatus.value : this.healthStatus,
    actionTaken: actionTaken.present ? actionTaken.value : this.actionTaken,
    localMediaId: localMediaId.present ? localMediaId.value : this.localMediaId,
    createdByVoice: createdByVoice ?? this.createdByVoice,
    healthScore: healthScore.present ? healthScore.value : this.healthScore,
  );
  Observation copyWithCompanion(ObservationsCompanion data) {
    return Observation(
      id: data.id.present ? data.id.value : this.id,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      type: data.type.present ? data.type.value : this.type,
      note: data.note.present ? data.note.value : this.note,
      healthStatus: data.healthStatus.present
          ? data.healthStatus.value
          : this.healthStatus,
      actionTaken: data.actionTaken.present
          ? data.actionTaken.value
          : this.actionTaken,
      localMediaId: data.localMediaId.present
          ? data.localMediaId.value
          : this.localMediaId,
      createdByVoice: data.createdByVoice.present
          ? data.createdByVoice.value
          : this.createdByVoice,
      healthScore: data.healthScore.present
          ? data.healthScore.value
          : this.healthScore,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Observation(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('type: $type, ')
          ..write('note: $note, ')
          ..write('healthStatus: $healthStatus, ')
          ..write('actionTaken: $actionTaken, ')
          ..write('localMediaId: $localMediaId, ')
          ..write('createdByVoice: $createdByVoice, ')
          ..write('healthScore: $healthScore')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    type,
    note,
    healthStatus,
    actionTaken,
    localMediaId,
    createdByVoice,
    healthScore,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Observation &&
          other.id == this.id &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.version == this.version &&
          other.syncState == this.syncState &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.sectionId == this.sectionId &&
          other.type == this.type &&
          other.note == this.note &&
          other.healthStatus == this.healthStatus &&
          other.actionTaken == this.actionTaken &&
          other.localMediaId == this.localMediaId &&
          other.createdByVoice == this.createdByVoice &&
          other.healthScore == this.healthScore);
}

class ObservationsCompanion extends UpdateCompanion<Observation> {
  final Value<String> id;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<int> version;
  final Value<String> syncState;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> sectionId;
  final Value<String> type;
  final Value<String> note;
  final Value<String?> healthStatus;
  final Value<String?> actionTaken;
  final Value<String?> localMediaId;
  final Value<bool> createdByVoice;
  final Value<int?> healthScore;
  final Value<int> rowid;
  const ObservationsCompanion({
    this.id = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.type = const Value.absent(),
    this.note = const Value.absent(),
    this.healthStatus = const Value.absent(),
    this.actionTaken = const Value.absent(),
    this.localMediaId = const Value.absent(),
    this.createdByVoice = const Value.absent(),
    this.healthScore = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationsCompanion.insert({
    required String id,
    required String farmId,
    required String ownerId,
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String sectionId,
    required String type,
    required String note,
    this.healthStatus = const Value.absent(),
    this.actionTaken = const Value.absent(),
    this.localMediaId = const Value.absent(),
    this.createdByVoice = const Value.absent(),
    this.healthScore = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       sectionId = Value(sectionId),
       type = Value(type),
       note = Value(note);
  static Insertable<Observation> custom({
    Expression<String>? id,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<int>? version,
    Expression<String>? syncState,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? sectionId,
    Expression<String>? type,
    Expression<String>? note,
    Expression<String>? healthStatus,
    Expression<String>? actionTaken,
    Expression<String>? localMediaId,
    Expression<bool>? createdByVoice,
    Expression<int>? healthScore,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (sectionId != null) 'section_id': sectionId,
      if (type != null) 'type': type,
      if (note != null) 'note': note,
      if (healthStatus != null) 'health_status': healthStatus,
      if (actionTaken != null) 'action_taken': actionTaken,
      if (localMediaId != null) 'local_media_id': localMediaId,
      if (createdByVoice != null) 'created_by_voice': createdByVoice,
      if (healthScore != null) 'health_score': healthScore,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationsCompanion copyWith({
    Value<String>? id,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<int>? version,
    Value<String>? syncState,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? sectionId,
    Value<String>? type,
    Value<String>? note,
    Value<String?>? healthStatus,
    Value<String?>? actionTaken,
    Value<String?>? localMediaId,
    Value<bool>? createdByVoice,
    Value<int?>? healthScore,
    Value<int>? rowid,
  }) {
    return ObservationsCompanion(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      sectionId: sectionId ?? this.sectionId,
      type: type ?? this.type,
      note: note ?? this.note,
      healthStatus: healthStatus ?? this.healthStatus,
      actionTaken: actionTaken ?? this.actionTaken,
      localMediaId: localMediaId ?? this.localMediaId,
      createdByVoice: createdByVoice ?? this.createdByVoice,
      healthScore: healthScore ?? this.healthScore,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (healthStatus.present) {
      map['health_status'] = Variable<String>(healthStatus.value);
    }
    if (actionTaken.present) {
      map['action_taken'] = Variable<String>(actionTaken.value);
    }
    if (localMediaId.present) {
      map['local_media_id'] = Variable<String>(localMediaId.value);
    }
    if (createdByVoice.present) {
      map['created_by_voice'] = Variable<bool>(createdByVoice.value);
    }
    if (healthScore.present) {
      map['health_score'] = Variable<int>(healthScore.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationsCompanion(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('type: $type, ')
          ..write('note: $note, ')
          ..write('healthStatus: $healthStatus, ')
          ..write('actionTaken: $actionTaken, ')
          ..write('localMediaId: $localMediaId, ')
          ..write('createdByVoice: $createdByVoice, ')
          ..write('healthScore: $healthScore, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FarmTasksTable extends FarmTasks
    with TableInfo<$FarmTasksTable, FarmTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FarmTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _expectedCostCentsMeta = const VerificationMeta(
    'expectedCostCents',
  );
  @override
  late final GeneratedColumn<int> expectedCostCents = GeneratedColumn<int>(
    'expected_cost_cents',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    title,
    description,
    dueDate,
    status,
    expectedCostCents,
    planId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'farm_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<FarmTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('expected_cost_cents')) {
      context.handle(
        _expectedCostCentsMeta,
        expectedCostCents.isAcceptableOrUnknown(
          data['expected_cost_cents']!,
          _expectedCostCentsMeta,
        ),
      );
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FarmTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FarmTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      expectedCostCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_cost_cents'],
      ),
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      ),
    );
  }

  @override
  $FarmTasksTable createAlias(String alias) {
    return $FarmTasksTable(attachedDatabase, alias);
  }
}

class FarmTask extends DataClass implements Insertable<FarmTask> {
  final String id;
  final String farmId;
  final String ownerId;
  final int version;
  final String syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String sectionId;
  final String title;
  final String? description;

  /// `Date` on the server. Stored at local midnight; nothing reads a time.
  final DateTime dueDate;
  final String status;
  final int? expectedCostCents;

  /// LOCAL-ONLY. The `saved_plans` row whose acceptance generated this step,
  /// or null for a task a person created.
  ///
  /// The server's `farm_tasks` has no such column, and the distinction it
  /// carries is not cosmetic: accepting a new plan retires the schedule the
  /// last one generated, and it has to be able to tell those steps apart from
  /// the reminder the farmer typed themselves. Without it the choice is
  /// between leaving two schedules on the timeline and deleting the farmer's
  /// own reminder, and both are wrong.
  final String? planId;
  const FarmTask({
    required this.id,
    required this.farmId,
    required this.ownerId,
    required this.version,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.sectionId,
    required this.title,
    this.description,
    required this.dueDate,
    required this.status,
    this.expectedCostCents,
    this.planId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['section_id'] = Variable<String>(sectionId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['due_date'] = Variable<DateTime>(dueDate);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || expectedCostCents != null) {
      map['expected_cost_cents'] = Variable<int>(expectedCostCents);
    }
    if (!nullToAbsent || planId != null) {
      map['plan_id'] = Variable<String>(planId);
    }
    return map;
  }

  FarmTasksCompanion toCompanion(bool nullToAbsent) {
    return FarmTasksCompanion(
      id: Value(id),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      version: Value(version),
      syncState: Value(syncState),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      sectionId: Value(sectionId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      dueDate: Value(dueDate),
      status: Value(status),
      expectedCostCents: expectedCostCents == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedCostCents),
      planId: planId == null && nullToAbsent
          ? const Value.absent()
          : Value(planId),
    );
  }

  factory FarmTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FarmTask(
      id: serializer.fromJson<String>(json['id']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      dueDate: serializer.fromJson<DateTime>(json['dueDate']),
      status: serializer.fromJson<String>(json['status']),
      expectedCostCents: serializer.fromJson<int?>(json['expectedCostCents']),
      planId: serializer.fromJson<String?>(json['planId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'sectionId': serializer.toJson<String>(sectionId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'dueDate': serializer.toJson<DateTime>(dueDate),
      'status': serializer.toJson<String>(status),
      'expectedCostCents': serializer.toJson<int?>(expectedCostCents),
      'planId': serializer.toJson<String?>(planId),
    };
  }

  FarmTask copyWith({
    String? id,
    String? farmId,
    String? ownerId,
    int? version,
    String? syncState,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? sectionId,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? dueDate,
    String? status,
    Value<int?> expectedCostCents = const Value.absent(),
    Value<String?> planId = const Value.absent(),
  }) => FarmTask(
    id: id ?? this.id,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    sectionId: sectionId ?? this.sectionId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    dueDate: dueDate ?? this.dueDate,
    status: status ?? this.status,
    expectedCostCents: expectedCostCents.present
        ? expectedCostCents.value
        : this.expectedCostCents,
    planId: planId.present ? planId.value : this.planId,
  );
  FarmTask copyWithCompanion(FarmTasksCompanion data) {
    return FarmTask(
      id: data.id.present ? data.id.value : this.id,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      status: data.status.present ? data.status.value : this.status,
      expectedCostCents: data.expectedCostCents.present
          ? data.expectedCostCents.value
          : this.expectedCostCents,
      planId: data.planId.present ? data.planId.value : this.planId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FarmTask(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('expectedCostCents: $expectedCostCents, ')
          ..write('planId: $planId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    title,
    description,
    dueDate,
    status,
    expectedCostCents,
    planId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FarmTask &&
          other.id == this.id &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.version == this.version &&
          other.syncState == this.syncState &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.sectionId == this.sectionId &&
          other.title == this.title &&
          other.description == this.description &&
          other.dueDate == this.dueDate &&
          other.status == this.status &&
          other.expectedCostCents == this.expectedCostCents &&
          other.planId == this.planId);
}

class FarmTasksCompanion extends UpdateCompanion<FarmTask> {
  final Value<String> id;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<int> version;
  final Value<String> syncState;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> sectionId;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime> dueDate;
  final Value<String> status;
  final Value<int?> expectedCostCents;
  final Value<String?> planId;
  final Value<int> rowid;
  const FarmTasksCompanion({
    this.id = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.status = const Value.absent(),
    this.expectedCostCents = const Value.absent(),
    this.planId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FarmTasksCompanion.insert({
    required String id,
    required String farmId,
    required String ownerId,
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String sectionId,
    required String title,
    this.description = const Value.absent(),
    required DateTime dueDate,
    this.status = const Value.absent(),
    this.expectedCostCents = const Value.absent(),
    this.planId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       sectionId = Value(sectionId),
       title = Value(title),
       dueDate = Value(dueDate);
  static Insertable<FarmTask> custom({
    Expression<String>? id,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<int>? version,
    Expression<String>? syncState,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? sectionId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<DateTime>? dueDate,
    Expression<String>? status,
    Expression<int>? expectedCostCents,
    Expression<String>? planId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (sectionId != null) 'section_id': sectionId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (dueDate != null) 'due_date': dueDate,
      if (status != null) 'status': status,
      if (expectedCostCents != null) 'expected_cost_cents': expectedCostCents,
      if (planId != null) 'plan_id': planId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FarmTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<int>? version,
    Value<String>? syncState,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? sectionId,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime>? dueDate,
    Value<String>? status,
    Value<int?>? expectedCostCents,
    Value<String?>? planId,
    Value<int>? rowid,
  }) {
    return FarmTasksCompanion(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      sectionId: sectionId ?? this.sectionId,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      expectedCostCents: expectedCostCents ?? this.expectedCostCents,
      planId: planId ?? this.planId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (expectedCostCents.present) {
      map['expected_cost_cents'] = Variable<int>(expectedCostCents.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FarmTasksCompanion(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('expectedCostCents: $expectedCostCents, ')
          ..write('planId: $planId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FinancialRecordsTable extends FinancialRecords
    with TableInfo<$FinancialRecordsTable, FinancialRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinancialRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    type,
    category,
    amountCents,
    date,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'financial_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<FinancialRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FinancialRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FinancialRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $FinancialRecordsTable createAlias(String alias) {
    return $FinancialRecordsTable(attachedDatabase, alias);
  }
}

class FinancialRecord extends DataClass implements Insertable<FinancialRecord> {
  final String id;
  final String farmId;
  final String ownerId;
  final int version;
  final String syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? sectionId;
  final String type;
  final String category;
  final int amountCents;
  final DateTime date;
  final String? note;
  const FinancialRecord({
    required this.id,
    required this.farmId,
    required this.ownerId,
    required this.version,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.sectionId,
    required this.type,
    required this.category,
    required this.amountCents,
    required this.date,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || sectionId != null) {
      map['section_id'] = Variable<String>(sectionId);
    }
    map['type'] = Variable<String>(type);
    map['category'] = Variable<String>(category);
    map['amount_cents'] = Variable<int>(amountCents);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  FinancialRecordsCompanion toCompanion(bool nullToAbsent) {
    return FinancialRecordsCompanion(
      id: Value(id),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      version: Value(version),
      syncState: Value(syncState),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      sectionId: sectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sectionId),
      type: Value(type),
      category: Value(category),
      amountCents: Value(amountCents),
      date: Value(date),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory FinancialRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FinancialRecord(
      id: serializer.fromJson<String>(json['id']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      sectionId: serializer.fromJson<String?>(json['sectionId']),
      type: serializer.fromJson<String>(json['type']),
      category: serializer.fromJson<String>(json['category']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      date: serializer.fromJson<DateTime>(json['date']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'sectionId': serializer.toJson<String?>(sectionId),
      'type': serializer.toJson<String>(type),
      'category': serializer.toJson<String>(category),
      'amountCents': serializer.toJson<int>(amountCents),
      'date': serializer.toJson<DateTime>(date),
      'note': serializer.toJson<String?>(note),
    };
  }

  FinancialRecord copyWith({
    String? id,
    String? farmId,
    String? ownerId,
    int? version,
    String? syncState,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<String?> sectionId = const Value.absent(),
    String? type,
    String? category,
    int? amountCents,
    DateTime? date,
    Value<String?> note = const Value.absent(),
  }) => FinancialRecord(
    id: id ?? this.id,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    sectionId: sectionId.present ? sectionId.value : this.sectionId,
    type: type ?? this.type,
    category: category ?? this.category,
    amountCents: amountCents ?? this.amountCents,
    date: date ?? this.date,
    note: note.present ? note.value : this.note,
  );
  FinancialRecord copyWithCompanion(FinancialRecordsCompanion data) {
    return FinancialRecord(
      id: data.id.present ? data.id.value : this.id,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      type: data.type.present ? data.type.value : this.type,
      category: data.category.present ? data.category.value : this.category,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      date: data.date.present ? data.date.value : this.date,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FinancialRecord(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('type: $type, ')
          ..write('category: $category, ')
          ..write('amountCents: $amountCents, ')
          ..write('date: $date, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    type,
    category,
    amountCents,
    date,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinancialRecord &&
          other.id == this.id &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.version == this.version &&
          other.syncState == this.syncState &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.sectionId == this.sectionId &&
          other.type == this.type &&
          other.category == this.category &&
          other.amountCents == this.amountCents &&
          other.date == this.date &&
          other.note == this.note);
}

class FinancialRecordsCompanion extends UpdateCompanion<FinancialRecord> {
  final Value<String> id;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<int> version;
  final Value<String> syncState;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String?> sectionId;
  final Value<String> type;
  final Value<String> category;
  final Value<int> amountCents;
  final Value<DateTime> date;
  final Value<String?> note;
  final Value<int> rowid;
  const FinancialRecordsCompanion({
    this.id = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.type = const Value.absent(),
    this.category = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.date = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FinancialRecordsCompanion.insert({
    required String id,
    required String farmId,
    required String ownerId,
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.sectionId = const Value.absent(),
    required String type,
    required String category,
    required int amountCents,
    required DateTime date,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       type = Value(type),
       category = Value(category),
       amountCents = Value(amountCents),
       date = Value(date);
  static Insertable<FinancialRecord> custom({
    Expression<String>? id,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<int>? version,
    Expression<String>? syncState,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? sectionId,
    Expression<String>? type,
    Expression<String>? category,
    Expression<int>? amountCents,
    Expression<DateTime>? date,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (sectionId != null) 'section_id': sectionId,
      if (type != null) 'type': type,
      if (category != null) 'category': category,
      if (amountCents != null) 'amount_cents': amountCents,
      if (date != null) 'date': date,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FinancialRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<int>? version,
    Value<String>? syncState,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String?>? sectionId,
    Value<String>? type,
    Value<String>? category,
    Value<int>? amountCents,
    Value<DateTime>? date,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return FinancialRecordsCompanion(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      sectionId: sectionId ?? this.sectionId,
      type: type ?? this.type,
      category: category ?? this.category,
      amountCents: amountCents ?? this.amountCents,
      date: date ?? this.date,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinancialRecordsCompanion(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('type: $type, ')
          ..write('category: $category, ')
          ..write('amountCents: $amountCents, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedPlansTable extends SavedPlans
    with TableInfo<$SavedPlansTable, SavedPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('saved'),
  );
  static const VerificationMeta _planMeta = const VerificationMeta('plan');
  @override
  late final GeneratedColumn<String> plan = GeneratedColumn<String>(
    'plan',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _approvedAtMeta = const VerificationMeta(
    'approvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> approvedAt = GeneratedColumn<DateTime>(
    'approved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    status,
    plan,
    approvedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('plan')) {
      context.handle(
        _planMeta,
        plan.isAcceptableOrUnknown(data['plan']!, _planMeta),
      );
    } else if (isInserting) {
      context.missing(_planMeta);
    }
    if (data.containsKey('approved_at')) {
      context.handle(
        _approvedAtMeta,
        approvedAt.isAcceptableOrUnknown(data['approved_at']!, _approvedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedPlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      plan: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan'],
      )!,
      approvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}approved_at'],
      ),
    );
  }

  @override
  $SavedPlansTable createAlias(String alias) {
    return $SavedPlansTable(attachedDatabase, alias);
  }
}

class SavedPlan extends DataClass implements Insertable<SavedPlan> {
  final String id;
  final String farmId;
  final String ownerId;
  final int version;
  final String syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String sectionId;
  final String status;

  /// The planner result, verbatim. Stored as the JSON text the server stores,
  /// not as parsed columns, so nothing is lost on the way back up.
  final String plan;
  final DateTime? approvedAt;
  const SavedPlan({
    required this.id,
    required this.farmId,
    required this.ownerId,
    required this.version,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.sectionId,
    required this.status,
    required this.plan,
    this.approvedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['version'] = Variable<int>(version);
    map['sync_state'] = Variable<String>(syncState);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['section_id'] = Variable<String>(sectionId);
    map['status'] = Variable<String>(status);
    map['plan'] = Variable<String>(plan);
    if (!nullToAbsent || approvedAt != null) {
      map['approved_at'] = Variable<DateTime>(approvedAt);
    }
    return map;
  }

  SavedPlansCompanion toCompanion(bool nullToAbsent) {
    return SavedPlansCompanion(
      id: Value(id),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      version: Value(version),
      syncState: Value(syncState),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      sectionId: Value(sectionId),
      status: Value(status),
      plan: Value(plan),
      approvedAt: approvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(approvedAt),
    );
  }

  factory SavedPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedPlan(
      id: serializer.fromJson<String>(json['id']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      version: serializer.fromJson<int>(json['version']),
      syncState: serializer.fromJson<String>(json['syncState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      status: serializer.fromJson<String>(json['status']),
      plan: serializer.fromJson<String>(json['plan']),
      approvedAt: serializer.fromJson<DateTime?>(json['approvedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'version': serializer.toJson<int>(version),
      'syncState': serializer.toJson<String>(syncState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'sectionId': serializer.toJson<String>(sectionId),
      'status': serializer.toJson<String>(status),
      'plan': serializer.toJson<String>(plan),
      'approvedAt': serializer.toJson<DateTime?>(approvedAt),
    };
  }

  SavedPlan copyWith({
    String? id,
    String? farmId,
    String? ownerId,
    int? version,
    String? syncState,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? sectionId,
    String? status,
    String? plan,
    Value<DateTime?> approvedAt = const Value.absent(),
  }) => SavedPlan(
    id: id ?? this.id,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    version: version ?? this.version,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    sectionId: sectionId ?? this.sectionId,
    status: status ?? this.status,
    plan: plan ?? this.plan,
    approvedAt: approvedAt.present ? approvedAt.value : this.approvedAt,
  );
  SavedPlan copyWithCompanion(SavedPlansCompanion data) {
    return SavedPlan(
      id: data.id.present ? data.id.value : this.id,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      version: data.version.present ? data.version.value : this.version,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      status: data.status.present ? data.status.value : this.status,
      plan: data.plan.present ? data.plan.value : this.plan,
      approvedAt: data.approvedAt.present
          ? data.approvedAt.value
          : this.approvedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlan(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('status: $status, ')
          ..write('plan: $plan, ')
          ..write('approvedAt: $approvedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    farmId,
    ownerId,
    version,
    syncState,
    createdAt,
    updatedAt,
    deletedAt,
    sectionId,
    status,
    plan,
    approvedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedPlan &&
          other.id == this.id &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.version == this.version &&
          other.syncState == this.syncState &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.sectionId == this.sectionId &&
          other.status == this.status &&
          other.plan == this.plan &&
          other.approvedAt == this.approvedAt);
}

class SavedPlansCompanion extends UpdateCompanion<SavedPlan> {
  final Value<String> id;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<int> version;
  final Value<String> syncState;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> sectionId;
  final Value<String> status;
  final Value<String> plan;
  final Value<DateTime?> approvedAt;
  final Value<int> rowid;
  const SavedPlansCompanion({
    this.id = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.status = const Value.absent(),
    this.plan = const Value.absent(),
    this.approvedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedPlansCompanion.insert({
    required String id,
    required String farmId,
    required String ownerId,
    this.version = const Value.absent(),
    this.syncState = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String sectionId,
    this.status = const Value.absent(),
    required String plan,
    this.approvedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       sectionId = Value(sectionId),
       plan = Value(plan);
  static Insertable<SavedPlan> custom({
    Expression<String>? id,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<int>? version,
    Expression<String>? syncState,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? sectionId,
    Expression<String>? status,
    Expression<String>? plan,
    Expression<DateTime>? approvedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (version != null) 'version': version,
      if (syncState != null) 'sync_state': syncState,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (sectionId != null) 'section_id': sectionId,
      if (status != null) 'status': status,
      if (plan != null) 'plan': plan,
      if (approvedAt != null) 'approved_at': approvedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedPlansCompanion copyWith({
    Value<String>? id,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<int>? version,
    Value<String>? syncState,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? sectionId,
    Value<String>? status,
    Value<String>? plan,
    Value<DateTime?>? approvedAt,
    Value<int>? rowid,
  }) {
    return SavedPlansCompanion(
      id: id ?? this.id,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      sectionId: sectionId ?? this.sectionId,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      approvedAt: approvedAt ?? this.approvedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (plan.present) {
      map['plan'] = Variable<String>(plan.value);
    }
    if (approvedAt.present) {
      map['approved_at'] = Variable<DateTime>(approvedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlansCompanion(')
          ..write('id: $id, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('version: $version, ')
          ..write('syncState: $syncState, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('status: $status, ')
          ..write('plan: $plan, ')
          ..write('approvedAt: $approvedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SectionProjectionsTable extends SectionProjections
    with TableInfo<$SectionProjectionsTable, SectionProjection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SectionProjectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedProfitCentsMeta =
      const VerificationMeta('expectedProfitCents');
  @override
  late final GeneratedColumn<int> expectedProfitCents = GeneratedColumn<int>(
    'expected_profit_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedCostCentsMeta = const VerificationMeta(
    'expectedCostCents',
  );
  @override
  late final GeneratedColumn<int> expectedCostCents = GeneratedColumn<int>(
    'expected_cost_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _harvestStartMeta = const VerificationMeta(
    'harvestStart',
  );
  @override
  late final GeneratedColumn<DateTime> harvestStart = GeneratedColumn<DateTime>(
    'harvest_start',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _harvestEndMeta = const VerificationMeta(
    'harvestEnd',
  );
  @override
  late final GeneratedColumn<DateTime> harvestEnd = GeneratedColumn<DateTime>(
    'harvest_end',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sectionId,
    expectedProfitCents,
    expectedCostCents,
    harvestStart,
    harvestEnd,
    planId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'section_projections';
  @override
  VerificationContext validateIntegrity(
    Insertable<SectionProjection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('expected_profit_cents')) {
      context.handle(
        _expectedProfitCentsMeta,
        expectedProfitCents.isAcceptableOrUnknown(
          data['expected_profit_cents']!,
          _expectedProfitCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedProfitCentsMeta);
    }
    if (data.containsKey('expected_cost_cents')) {
      context.handle(
        _expectedCostCentsMeta,
        expectedCostCents.isAcceptableOrUnknown(
          data['expected_cost_cents']!,
          _expectedCostCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedCostCentsMeta);
    }
    if (data.containsKey('harvest_start')) {
      context.handle(
        _harvestStartMeta,
        harvestStart.isAcceptableOrUnknown(
          data['harvest_start']!,
          _harvestStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_harvestStartMeta);
    }
    if (data.containsKey('harvest_end')) {
      context.handle(
        _harvestEndMeta,
        harvestEnd.isAcceptableOrUnknown(data['harvest_end']!, _harvestEndMeta),
      );
    } else if (isInserting) {
      context.missing(_harvestEndMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sectionId};
  @override
  SectionProjection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SectionProjection(
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      expectedProfitCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_profit_cents'],
      )!,
      expectedCostCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_cost_cents'],
      )!,
      harvestStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}harvest_start'],
      )!,
      harvestEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}harvest_end'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      ),
    );
  }

  @override
  $SectionProjectionsTable createAlias(String alias) {
    return $SectionProjectionsTable(attachedDatabase, alias);
  }
}

class SectionProjection extends DataClass
    implements Insertable<SectionProjection> {
  final String sectionId;
  final int expectedProfitCents;
  final int expectedCostCents;

  /// Harvest is a window, not a day count. "92 days" is derived from
  /// [harvestStart] at render time and is never stored.
  final DateTime harvestStart;
  final DateTime harvestEnd;
  final String? planId;
  const SectionProjection({
    required this.sectionId,
    required this.expectedProfitCents,
    required this.expectedCostCents,
    required this.harvestStart,
    required this.harvestEnd,
    this.planId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['section_id'] = Variable<String>(sectionId);
    map['expected_profit_cents'] = Variable<int>(expectedProfitCents);
    map['expected_cost_cents'] = Variable<int>(expectedCostCents);
    map['harvest_start'] = Variable<DateTime>(harvestStart);
    map['harvest_end'] = Variable<DateTime>(harvestEnd);
    if (!nullToAbsent || planId != null) {
      map['plan_id'] = Variable<String>(planId);
    }
    return map;
  }

  SectionProjectionsCompanion toCompanion(bool nullToAbsent) {
    return SectionProjectionsCompanion(
      sectionId: Value(sectionId),
      expectedProfitCents: Value(expectedProfitCents),
      expectedCostCents: Value(expectedCostCents),
      harvestStart: Value(harvestStart),
      harvestEnd: Value(harvestEnd),
      planId: planId == null && nullToAbsent
          ? const Value.absent()
          : Value(planId),
    );
  }

  factory SectionProjection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SectionProjection(
      sectionId: serializer.fromJson<String>(json['sectionId']),
      expectedProfitCents: serializer.fromJson<int>(
        json['expectedProfitCents'],
      ),
      expectedCostCents: serializer.fromJson<int>(json['expectedCostCents']),
      harvestStart: serializer.fromJson<DateTime>(json['harvestStart']),
      harvestEnd: serializer.fromJson<DateTime>(json['harvestEnd']),
      planId: serializer.fromJson<String?>(json['planId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sectionId': serializer.toJson<String>(sectionId),
      'expectedProfitCents': serializer.toJson<int>(expectedProfitCents),
      'expectedCostCents': serializer.toJson<int>(expectedCostCents),
      'harvestStart': serializer.toJson<DateTime>(harvestStart),
      'harvestEnd': serializer.toJson<DateTime>(harvestEnd),
      'planId': serializer.toJson<String?>(planId),
    };
  }

  SectionProjection copyWith({
    String? sectionId,
    int? expectedProfitCents,
    int? expectedCostCents,
    DateTime? harvestStart,
    DateTime? harvestEnd,
    Value<String?> planId = const Value.absent(),
  }) => SectionProjection(
    sectionId: sectionId ?? this.sectionId,
    expectedProfitCents: expectedProfitCents ?? this.expectedProfitCents,
    expectedCostCents: expectedCostCents ?? this.expectedCostCents,
    harvestStart: harvestStart ?? this.harvestStart,
    harvestEnd: harvestEnd ?? this.harvestEnd,
    planId: planId.present ? planId.value : this.planId,
  );
  SectionProjection copyWithCompanion(SectionProjectionsCompanion data) {
    return SectionProjection(
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      expectedProfitCents: data.expectedProfitCents.present
          ? data.expectedProfitCents.value
          : this.expectedProfitCents,
      expectedCostCents: data.expectedCostCents.present
          ? data.expectedCostCents.value
          : this.expectedCostCents,
      harvestStart: data.harvestStart.present
          ? data.harvestStart.value
          : this.harvestStart,
      harvestEnd: data.harvestEnd.present
          ? data.harvestEnd.value
          : this.harvestEnd,
      planId: data.planId.present ? data.planId.value : this.planId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SectionProjection(')
          ..write('sectionId: $sectionId, ')
          ..write('expectedProfitCents: $expectedProfitCents, ')
          ..write('expectedCostCents: $expectedCostCents, ')
          ..write('harvestStart: $harvestStart, ')
          ..write('harvestEnd: $harvestEnd, ')
          ..write('planId: $planId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sectionId,
    expectedProfitCents,
    expectedCostCents,
    harvestStart,
    harvestEnd,
    planId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SectionProjection &&
          other.sectionId == this.sectionId &&
          other.expectedProfitCents == this.expectedProfitCents &&
          other.expectedCostCents == this.expectedCostCents &&
          other.harvestStart == this.harvestStart &&
          other.harvestEnd == this.harvestEnd &&
          other.planId == this.planId);
}

class SectionProjectionsCompanion extends UpdateCompanion<SectionProjection> {
  final Value<String> sectionId;
  final Value<int> expectedProfitCents;
  final Value<int> expectedCostCents;
  final Value<DateTime> harvestStart;
  final Value<DateTime> harvestEnd;
  final Value<String?> planId;
  final Value<int> rowid;
  const SectionProjectionsCompanion({
    this.sectionId = const Value.absent(),
    this.expectedProfitCents = const Value.absent(),
    this.expectedCostCents = const Value.absent(),
    this.harvestStart = const Value.absent(),
    this.harvestEnd = const Value.absent(),
    this.planId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SectionProjectionsCompanion.insert({
    required String sectionId,
    required int expectedProfitCents,
    required int expectedCostCents,
    required DateTime harvestStart,
    required DateTime harvestEnd,
    this.planId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sectionId = Value(sectionId),
       expectedProfitCents = Value(expectedProfitCents),
       expectedCostCents = Value(expectedCostCents),
       harvestStart = Value(harvestStart),
       harvestEnd = Value(harvestEnd);
  static Insertable<SectionProjection> custom({
    Expression<String>? sectionId,
    Expression<int>? expectedProfitCents,
    Expression<int>? expectedCostCents,
    Expression<DateTime>? harvestStart,
    Expression<DateTime>? harvestEnd,
    Expression<String>? planId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sectionId != null) 'section_id': sectionId,
      if (expectedProfitCents != null)
        'expected_profit_cents': expectedProfitCents,
      if (expectedCostCents != null) 'expected_cost_cents': expectedCostCents,
      if (harvestStart != null) 'harvest_start': harvestStart,
      if (harvestEnd != null) 'harvest_end': harvestEnd,
      if (planId != null) 'plan_id': planId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SectionProjectionsCompanion copyWith({
    Value<String>? sectionId,
    Value<int>? expectedProfitCents,
    Value<int>? expectedCostCents,
    Value<DateTime>? harvestStart,
    Value<DateTime>? harvestEnd,
    Value<String?>? planId,
    Value<int>? rowid,
  }) {
    return SectionProjectionsCompanion(
      sectionId: sectionId ?? this.sectionId,
      expectedProfitCents: expectedProfitCents ?? this.expectedProfitCents,
      expectedCostCents: expectedCostCents ?? this.expectedCostCents,
      harvestStart: harvestStart ?? this.harvestStart,
      harvestEnd: harvestEnd ?? this.harvestEnd,
      planId: planId ?? this.planId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (expectedProfitCents.present) {
      map['expected_profit_cents'] = Variable<int>(expectedProfitCents.value);
    }
    if (expectedCostCents.present) {
      map['expected_cost_cents'] = Variable<int>(expectedCostCents.value);
    }
    if (harvestStart.present) {
      map['harvest_start'] = Variable<DateTime>(harvestStart.value);
    }
    if (harvestEnd.present) {
      map['harvest_end'] = Variable<DateTime>(harvestEnd.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SectionProjectionsCompanion(')
          ..write('sectionId: $sectionId, ')
          ..write('expectedProfitCents: $expectedProfitCents, ')
          ..write('expectedCostCents: $expectedCostCents, ')
          ..write('harvestStart: $harvestStart, ')
          ..write('harvestEnd: $harvestEnd, ')
          ..write('planId: $planId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SectionDetailsTable extends SectionDetails
    with TableInfo<$SectionDetailsTable, SectionDetail> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SectionDetailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _waterNoteMeta = const VerificationMeta(
    'waterNote',
  );
  @override
  late final GeneratedColumn<String> waterNote = GeneratedColumn<String>(
    'water_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _soilNoteMeta = const VerificationMeta(
    'soilNote',
  );
  @override
  late final GeneratedColumn<String> soilNote = GeneratedColumn<String>(
    'soil_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _marketNoteMeta = const VerificationMeta(
    'marketNote',
  );
  @override
  late final GeneratedColumn<String> marketNote = GeneratedColumn<String>(
    'market_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sectionId,
    description,
    waterNote,
    soilNote,
    marketNote,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'section_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<SectionDetail> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('water_note')) {
      context.handle(
        _waterNoteMeta,
        waterNote.isAcceptableOrUnknown(data['water_note']!, _waterNoteMeta),
      );
    }
    if (data.containsKey('soil_note')) {
      context.handle(
        _soilNoteMeta,
        soilNote.isAcceptableOrUnknown(data['soil_note']!, _soilNoteMeta),
      );
    }
    if (data.containsKey('market_note')) {
      context.handle(
        _marketNoteMeta,
        marketNote.isAcceptableOrUnknown(data['market_note']!, _marketNoteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sectionId};
  @override
  SectionDetail map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SectionDetail(
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      waterNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}water_note'],
      ),
      soilNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}soil_note'],
      ),
      marketNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}market_note'],
      ),
    );
  }

  @override
  $SectionDetailsTable createAlias(String alias) {
    return $SectionDetailsTable(attachedDatabase, alias);
  }
}

class SectionDetail extends DataClass implements Insertable<SectionDetail> {
  final String sectionId;
  final String? description;
  final String? waterNote;
  final String? soilNote;
  final String? marketNote;
  const SectionDetail({
    required this.sectionId,
    this.description,
    this.waterNote,
    this.soilNote,
    this.marketNote,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['section_id'] = Variable<String>(sectionId);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || waterNote != null) {
      map['water_note'] = Variable<String>(waterNote);
    }
    if (!nullToAbsent || soilNote != null) {
      map['soil_note'] = Variable<String>(soilNote);
    }
    if (!nullToAbsent || marketNote != null) {
      map['market_note'] = Variable<String>(marketNote);
    }
    return map;
  }

  SectionDetailsCompanion toCompanion(bool nullToAbsent) {
    return SectionDetailsCompanion(
      sectionId: Value(sectionId),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      waterNote: waterNote == null && nullToAbsent
          ? const Value.absent()
          : Value(waterNote),
      soilNote: soilNote == null && nullToAbsent
          ? const Value.absent()
          : Value(soilNote),
      marketNote: marketNote == null && nullToAbsent
          ? const Value.absent()
          : Value(marketNote),
    );
  }

  factory SectionDetail.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SectionDetail(
      sectionId: serializer.fromJson<String>(json['sectionId']),
      description: serializer.fromJson<String?>(json['description']),
      waterNote: serializer.fromJson<String?>(json['waterNote']),
      soilNote: serializer.fromJson<String?>(json['soilNote']),
      marketNote: serializer.fromJson<String?>(json['marketNote']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sectionId': serializer.toJson<String>(sectionId),
      'description': serializer.toJson<String?>(description),
      'waterNote': serializer.toJson<String?>(waterNote),
      'soilNote': serializer.toJson<String?>(soilNote),
      'marketNote': serializer.toJson<String?>(marketNote),
    };
  }

  SectionDetail copyWith({
    String? sectionId,
    Value<String?> description = const Value.absent(),
    Value<String?> waterNote = const Value.absent(),
    Value<String?> soilNote = const Value.absent(),
    Value<String?> marketNote = const Value.absent(),
  }) => SectionDetail(
    sectionId: sectionId ?? this.sectionId,
    description: description.present ? description.value : this.description,
    waterNote: waterNote.present ? waterNote.value : this.waterNote,
    soilNote: soilNote.present ? soilNote.value : this.soilNote,
    marketNote: marketNote.present ? marketNote.value : this.marketNote,
  );
  SectionDetail copyWithCompanion(SectionDetailsCompanion data) {
    return SectionDetail(
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      description: data.description.present
          ? data.description.value
          : this.description,
      waterNote: data.waterNote.present ? data.waterNote.value : this.waterNote,
      soilNote: data.soilNote.present ? data.soilNote.value : this.soilNote,
      marketNote: data.marketNote.present
          ? data.marketNote.value
          : this.marketNote,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SectionDetail(')
          ..write('sectionId: $sectionId, ')
          ..write('description: $description, ')
          ..write('waterNote: $waterNote, ')
          ..write('soilNote: $soilNote, ')
          ..write('marketNote: $marketNote')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sectionId, description, waterNote, soilNote, marketNote);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SectionDetail &&
          other.sectionId == this.sectionId &&
          other.description == this.description &&
          other.waterNote == this.waterNote &&
          other.soilNote == this.soilNote &&
          other.marketNote == this.marketNote);
}

class SectionDetailsCompanion extends UpdateCompanion<SectionDetail> {
  final Value<String> sectionId;
  final Value<String?> description;
  final Value<String?> waterNote;
  final Value<String?> soilNote;
  final Value<String?> marketNote;
  final Value<int> rowid;
  const SectionDetailsCompanion({
    this.sectionId = const Value.absent(),
    this.description = const Value.absent(),
    this.waterNote = const Value.absent(),
    this.soilNote = const Value.absent(),
    this.marketNote = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SectionDetailsCompanion.insert({
    required String sectionId,
    this.description = const Value.absent(),
    this.waterNote = const Value.absent(),
    this.soilNote = const Value.absent(),
    this.marketNote = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sectionId = Value(sectionId);
  static Insertable<SectionDetail> custom({
    Expression<String>? sectionId,
    Expression<String>? description,
    Expression<String>? waterNote,
    Expression<String>? soilNote,
    Expression<String>? marketNote,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sectionId != null) 'section_id': sectionId,
      if (description != null) 'description': description,
      if (waterNote != null) 'water_note': waterNote,
      if (soilNote != null) 'soil_note': soilNote,
      if (marketNote != null) 'market_note': marketNote,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SectionDetailsCompanion copyWith({
    Value<String>? sectionId,
    Value<String?>? description,
    Value<String?>? waterNote,
    Value<String?>? soilNote,
    Value<String?>? marketNote,
    Value<int>? rowid,
  }) {
    return SectionDetailsCompanion(
      sectionId: sectionId ?? this.sectionId,
      description: description ?? this.description,
      waterNote: waterNote ?? this.waterNote,
      soilNote: soilNote ?? this.soilNote,
      marketNote: marketNote ?? this.marketNote,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (waterNote.present) {
      map['water_note'] = Variable<String>(waterNote.value);
    }
    if (soilNote.present) {
      map['soil_note'] = Variable<String>(soilNote.value);
    }
    if (marketNote.present) {
      map['market_note'] = Variable<String>(marketNote.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SectionDetailsCompanion(')
          ..write('sectionId: $sectionId, ')
          ..write('description: $description, ')
          ..write('waterNote: $waterNote, ')
          ..write('soilNote: $soilNote, ')
          ..write('marketNote: $marketNote, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMutationsTable extends SyncMutations
    with TableInfo<$SyncMutationsTable, SyncMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMutationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordTypeMeta = const VerificationMeta(
    'recordType',
  );
  @override
  late final GeneratedColumn<String> recordType = GeneratedColumn<String>(
    'record_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordVersionMeta = const VerificationMeta(
    'recordVersion',
  );
  @override
  late final GeneratedColumn<int> recordVersion = GeneratedColumn<int>(
    'record_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dependencyIdMeta = const VerificationMeta(
    'dependencyId',
  );
  @override
  late final GeneratedColumn<String> dependencyId = GeneratedColumn<String>(
    'dependency_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveryStateMeta = const VerificationMeta(
    'deliveryState',
  );
  @override
  late final GeneratedColumn<String> deliveryState = GeneratedColumn<String>(
    'delivery_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _budgetCountMeta = const VerificationMeta(
    'budgetCount',
  );
  @override
  late final GeneratedColumn<int> budgetCount = GeneratedColumn<int>(
    'budget_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mutationId,
    farmId,
    ownerId,
    operation,
    recordType,
    recordId,
    createdAt,
    syncedAt,
    payload,
    recordVersion,
    dependencyId,
    deliveryState,
    attemptCount,
    budgetCount,
    nextAttemptAt,
    errorCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('record_type')) {
      context.handle(
        _recordTypeMeta,
        recordType.isAcceptableOrUnknown(data['record_type']!, _recordTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_recordTypeMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('record_version')) {
      context.handle(
        _recordVersionMeta,
        recordVersion.isAcceptableOrUnknown(
          data['record_version']!,
          _recordVersionMeta,
        ),
      );
    }
    if (data.containsKey('dependency_id')) {
      context.handle(
        _dependencyIdMeta,
        dependencyId.isAcceptableOrUnknown(
          data['dependency_id']!,
          _dependencyIdMeta,
        ),
      );
    }
    if (data.containsKey('delivery_state')) {
      context.handle(
        _deliveryStateMeta,
        deliveryState.isAcceptableOrUnknown(
          data['delivery_state']!,
          _deliveryStateMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('budget_count')) {
      context.handle(
        _budgetCountMeta,
        budgetCount.isAcceptableOrUnknown(
          data['budget_count']!,
          _budgetCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mutationId};
  @override
  SyncMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMutation(
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      recordType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_type'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      recordVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}record_version'],
      ),
      dependencyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dependency_id'],
      ),
      deliveryState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      budgetCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}budget_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
    );
  }

  @override
  $SyncMutationsTable createAlias(String alias) {
    return $SyncMutationsTable(attachedDatabase, alias);
  }
}

class SyncMutation extends DataClass implements Insertable<SyncMutation> {
  final String mutationId;
  final String farmId;
  final String ownerId;
  final String operation;
  final String recordType;
  final String recordId;
  final DateTime createdAt;

  /// Null until the server has acknowledged it. The count of nulls is what
  /// "3 changes waiting" shows.
  final DateTime? syncedAt;
  final String? payload;
  final int? recordVersion;
  final String? dependencyId;
  final String deliveryState;
  final int attemptCount;
  final int budgetCount;
  final DateTime? nextAttemptAt;
  final String? errorCode;
  const SyncMutation({
    required this.mutationId,
    required this.farmId,
    required this.ownerId,
    required this.operation,
    required this.recordType,
    required this.recordId,
    required this.createdAt,
    this.syncedAt,
    this.payload,
    this.recordVersion,
    this.dependencyId,
    required this.deliveryState,
    required this.attemptCount,
    required this.budgetCount,
    this.nextAttemptAt,
    this.errorCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mutation_id'] = Variable<String>(mutationId);
    map['farm_id'] = Variable<String>(farmId);
    map['owner_id'] = Variable<String>(ownerId);
    map['operation'] = Variable<String>(operation);
    map['record_type'] = Variable<String>(recordType);
    map['record_id'] = Variable<String>(recordId);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    if (!nullToAbsent || recordVersion != null) {
      map['record_version'] = Variable<int>(recordVersion);
    }
    if (!nullToAbsent || dependencyId != null) {
      map['dependency_id'] = Variable<String>(dependencyId);
    }
    map['delivery_state'] = Variable<String>(deliveryState);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['budget_count'] = Variable<int>(budgetCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    return map;
  }

  SyncMutationsCompanion toCompanion(bool nullToAbsent) {
    return SyncMutationsCompanion(
      mutationId: Value(mutationId),
      farmId: Value(farmId),
      ownerId: Value(ownerId),
      operation: Value(operation),
      recordType: Value(recordType),
      recordId: Value(recordId),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      recordVersion: recordVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(recordVersion),
      dependencyId: dependencyId == null && nullToAbsent
          ? const Value.absent()
          : Value(dependencyId),
      deliveryState: Value(deliveryState),
      attemptCount: Value(attemptCount),
      budgetCount: Value(budgetCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
    );
  }

  factory SyncMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMutation(
      mutationId: serializer.fromJson<String>(json['mutationId']),
      farmId: serializer.fromJson<String>(json['farmId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      operation: serializer.fromJson<String>(json['operation']),
      recordType: serializer.fromJson<String>(json['recordType']),
      recordId: serializer.fromJson<String>(json['recordId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      payload: serializer.fromJson<String?>(json['payload']),
      recordVersion: serializer.fromJson<int?>(json['recordVersion']),
      dependencyId: serializer.fromJson<String?>(json['dependencyId']),
      deliveryState: serializer.fromJson<String>(json['deliveryState']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      budgetCount: serializer.fromJson<int>(json['budgetCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mutationId': serializer.toJson<String>(mutationId),
      'farmId': serializer.toJson<String>(farmId),
      'ownerId': serializer.toJson<String>(ownerId),
      'operation': serializer.toJson<String>(operation),
      'recordType': serializer.toJson<String>(recordType),
      'recordId': serializer.toJson<String>(recordId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'payload': serializer.toJson<String?>(payload),
      'recordVersion': serializer.toJson<int?>(recordVersion),
      'dependencyId': serializer.toJson<String?>(dependencyId),
      'deliveryState': serializer.toJson<String>(deliveryState),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'budgetCount': serializer.toJson<int>(budgetCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'errorCode': serializer.toJson<String?>(errorCode),
    };
  }

  SyncMutation copyWith({
    String? mutationId,
    String? farmId,
    String? ownerId,
    String? operation,
    String? recordType,
    String? recordId,
    DateTime? createdAt,
    Value<DateTime?> syncedAt = const Value.absent(),
    Value<String?> payload = const Value.absent(),
    Value<int?> recordVersion = const Value.absent(),
    Value<String?> dependencyId = const Value.absent(),
    String? deliveryState,
    int? attemptCount,
    int? budgetCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
  }) => SyncMutation(
    mutationId: mutationId ?? this.mutationId,
    farmId: farmId ?? this.farmId,
    ownerId: ownerId ?? this.ownerId,
    operation: operation ?? this.operation,
    recordType: recordType ?? this.recordType,
    recordId: recordId ?? this.recordId,
    createdAt: createdAt ?? this.createdAt,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    payload: payload.present ? payload.value : this.payload,
    recordVersion: recordVersion.present
        ? recordVersion.value
        : this.recordVersion,
    dependencyId: dependencyId.present ? dependencyId.value : this.dependencyId,
    deliveryState: deliveryState ?? this.deliveryState,
    attemptCount: attemptCount ?? this.attemptCount,
    budgetCount: budgetCount ?? this.budgetCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
  );
  SyncMutation copyWithCompanion(SyncMutationsCompanion data) {
    return SyncMutation(
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      operation: data.operation.present ? data.operation.value : this.operation,
      recordType: data.recordType.present
          ? data.recordType.value
          : this.recordType,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
      recordVersion: data.recordVersion.present
          ? data.recordVersion.value
          : this.recordVersion,
      dependencyId: data.dependencyId.present
          ? data.dependencyId.value
          : this.dependencyId,
      deliveryState: data.deliveryState.present
          ? data.deliveryState.value
          : this.deliveryState,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      budgetCount: data.budgetCount.present
          ? data.budgetCount.value
          : this.budgetCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMutation(')
          ..write('mutationId: $mutationId, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('operation: $operation, ')
          ..write('recordType: $recordType, ')
          ..write('recordId: $recordId, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('payload: $payload, ')
          ..write('recordVersion: $recordVersion, ')
          ..write('dependencyId: $dependencyId, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('budgetCount: $budgetCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('errorCode: $errorCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mutationId,
    farmId,
    ownerId,
    operation,
    recordType,
    recordId,
    createdAt,
    syncedAt,
    payload,
    recordVersion,
    dependencyId,
    deliveryState,
    attemptCount,
    budgetCount,
    nextAttemptAt,
    errorCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMutation &&
          other.mutationId == this.mutationId &&
          other.farmId == this.farmId &&
          other.ownerId == this.ownerId &&
          other.operation == this.operation &&
          other.recordType == this.recordType &&
          other.recordId == this.recordId &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt &&
          other.payload == this.payload &&
          other.recordVersion == this.recordVersion &&
          other.dependencyId == this.dependencyId &&
          other.deliveryState == this.deliveryState &&
          other.attemptCount == this.attemptCount &&
          other.budgetCount == this.budgetCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.errorCode == this.errorCode);
}

class SyncMutationsCompanion extends UpdateCompanion<SyncMutation> {
  final Value<String> mutationId;
  final Value<String> farmId;
  final Value<String> ownerId;
  final Value<String> operation;
  final Value<String> recordType;
  final Value<String> recordId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<String?> payload;
  final Value<int?> recordVersion;
  final Value<String?> dependencyId;
  final Value<String> deliveryState;
  final Value<int> attemptCount;
  final Value<int> budgetCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> errorCode;
  final Value<int> rowid;
  const SyncMutationsCompanion({
    this.mutationId = const Value.absent(),
    this.farmId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.operation = const Value.absent(),
    this.recordType = const Value.absent(),
    this.recordId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.recordVersion = const Value.absent(),
    this.dependencyId = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.budgetCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMutationsCompanion.insert({
    required String mutationId,
    required String farmId,
    required String ownerId,
    required String operation,
    required String recordType,
    required String recordId,
    required DateTime createdAt,
    this.syncedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.recordVersion = const Value.absent(),
    this.dependencyId = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.budgetCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mutationId = Value(mutationId),
       farmId = Value(farmId),
       ownerId = Value(ownerId),
       operation = Value(operation),
       recordType = Value(recordType),
       recordId = Value(recordId),
       createdAt = Value(createdAt);
  static Insertable<SyncMutation> custom({
    Expression<String>? mutationId,
    Expression<String>? farmId,
    Expression<String>? ownerId,
    Expression<String>? operation,
    Expression<String>? recordType,
    Expression<String>? recordId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<String>? payload,
    Expression<int>? recordVersion,
    Expression<String>? dependencyId,
    Expression<String>? deliveryState,
    Expression<int>? attemptCount,
    Expression<int>? budgetCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? errorCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mutationId != null) 'mutation_id': mutationId,
      if (farmId != null) 'farm_id': farmId,
      if (ownerId != null) 'owner_id': ownerId,
      if (operation != null) 'operation': operation,
      if (recordType != null) 'record_type': recordType,
      if (recordId != null) 'record_id': recordId,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (payload != null) 'payload': payload,
      if (recordVersion != null) 'record_version': recordVersion,
      if (dependencyId != null) 'dependency_id': dependencyId,
      if (deliveryState != null) 'delivery_state': deliveryState,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (budgetCount != null) 'budget_count': budgetCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (errorCode != null) 'error_code': errorCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMutationsCompanion copyWith({
    Value<String>? mutationId,
    Value<String>? farmId,
    Value<String>? ownerId,
    Value<String>? operation,
    Value<String>? recordType,
    Value<String>? recordId,
    Value<DateTime>? createdAt,
    Value<DateTime?>? syncedAt,
    Value<String?>? payload,
    Value<int?>? recordVersion,
    Value<String?>? dependencyId,
    Value<String>? deliveryState,
    Value<int>? attemptCount,
    Value<int>? budgetCount,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? errorCode,
    Value<int>? rowid,
  }) {
    return SyncMutationsCompanion(
      mutationId: mutationId ?? this.mutationId,
      farmId: farmId ?? this.farmId,
      ownerId: ownerId ?? this.ownerId,
      operation: operation ?? this.operation,
      recordType: recordType ?? this.recordType,
      recordId: recordId ?? this.recordId,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      payload: payload ?? this.payload,
      recordVersion: recordVersion ?? this.recordVersion,
      dependencyId: dependencyId ?? this.dependencyId,
      deliveryState: deliveryState ?? this.deliveryState,
      attemptCount: attemptCount ?? this.attemptCount,
      budgetCount: budgetCount ?? this.budgetCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      errorCode: errorCode ?? this.errorCode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (recordType.present) {
      map['record_type'] = Variable<String>(recordType.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (recordVersion.present) {
      map['record_version'] = Variable<int>(recordVersion.value);
    }
    if (dependencyId.present) {
      map['dependency_id'] = Variable<String>(dependencyId.value);
    }
    if (deliveryState.present) {
      map['delivery_state'] = Variable<String>(deliveryState.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (budgetCount.present) {
      map['budget_count'] = Variable<int>(budgetCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMutationsCompanion(')
          ..write('mutationId: $mutationId, ')
          ..write('farmId: $farmId, ')
          ..write('ownerId: $ownerId, ')
          ..write('operation: $operation, ')
          ..write('recordType: $recordType, ')
          ..write('recordId: $recordId, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('payload: $payload, ')
          ..write('recordVersion: $recordVersion, ')
          ..write('dependencyId: $dependencyId, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('budgetCount: $budgetCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('errorCode: $errorCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeedStateTable extends SeedState
    with TableInfo<$SeedStateTable, SeedStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeedStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seedVersionMeta = const VerificationMeta(
    'seedVersion',
  );
  @override
  late final GeneratedColumn<String> seedVersion = GeneratedColumn<String>(
    'seed_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seededAtMeta = const VerificationMeta(
    'seededAt',
  );
  @override
  late final GeneratedColumn<DateTime> seededAt = GeneratedColumn<DateTime>(
    'seeded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, seedVersion, seededAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seed_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeedStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('seed_version')) {
      context.handle(
        _seedVersionMeta,
        seedVersion.isAcceptableOrUnknown(
          data['seed_version']!,
          _seedVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_seedVersionMeta);
    }
    if (data.containsKey('seeded_at')) {
      context.handle(
        _seededAtMeta,
        seededAt.isAcceptableOrUnknown(data['seeded_at']!, _seededAtMeta),
      );
    } else if (isInserting) {
      context.missing(_seededAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SeedStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeedStateData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      seedVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}seed_version'],
      )!,
      seededAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}seeded_at'],
      )!,
    );
  }

  @override
  $SeedStateTable createAlias(String alias) {
    return $SeedStateTable(attachedDatabase, alias);
  }
}

class SeedStateData extends DataClass implements Insertable<SeedStateData> {
  final int id;
  final String seedVersion;
  final DateTime seededAt;
  const SeedStateData({
    required this.id,
    required this.seedVersion,
    required this.seededAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['seed_version'] = Variable<String>(seedVersion);
    map['seeded_at'] = Variable<DateTime>(seededAt);
    return map;
  }

  SeedStateCompanion toCompanion(bool nullToAbsent) {
    return SeedStateCompanion(
      id: Value(id),
      seedVersion: Value(seedVersion),
      seededAt: Value(seededAt),
    );
  }

  factory SeedStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeedStateData(
      id: serializer.fromJson<int>(json['id']),
      seedVersion: serializer.fromJson<String>(json['seedVersion']),
      seededAt: serializer.fromJson<DateTime>(json['seededAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seedVersion': serializer.toJson<String>(seedVersion),
      'seededAt': serializer.toJson<DateTime>(seededAt),
    };
  }

  SeedStateData copyWith({int? id, String? seedVersion, DateTime? seededAt}) =>
      SeedStateData(
        id: id ?? this.id,
        seedVersion: seedVersion ?? this.seedVersion,
        seededAt: seededAt ?? this.seededAt,
      );
  SeedStateData copyWithCompanion(SeedStateCompanion data) {
    return SeedStateData(
      id: data.id.present ? data.id.value : this.id,
      seedVersion: data.seedVersion.present
          ? data.seedVersion.value
          : this.seedVersion,
      seededAt: data.seededAt.present ? data.seededAt.value : this.seededAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeedStateData(')
          ..write('id: $id, ')
          ..write('seedVersion: $seedVersion, ')
          ..write('seededAt: $seededAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, seedVersion, seededAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeedStateData &&
          other.id == this.id &&
          other.seedVersion == this.seedVersion &&
          other.seededAt == this.seededAt);
}

class SeedStateCompanion extends UpdateCompanion<SeedStateData> {
  final Value<int> id;
  final Value<String> seedVersion;
  final Value<DateTime> seededAt;
  const SeedStateCompanion({
    this.id = const Value.absent(),
    this.seedVersion = const Value.absent(),
    this.seededAt = const Value.absent(),
  });
  SeedStateCompanion.insert({
    this.id = const Value.absent(),
    required String seedVersion,
    required DateTime seededAt,
  }) : seedVersion = Value(seedVersion),
       seededAt = Value(seededAt);
  static Insertable<SeedStateData> custom({
    Expression<int>? id,
    Expression<String>? seedVersion,
    Expression<DateTime>? seededAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seedVersion != null) 'seed_version': seedVersion,
      if (seededAt != null) 'seeded_at': seededAt,
    });
  }

  SeedStateCompanion copyWith({
    Value<int>? id,
    Value<String>? seedVersion,
    Value<DateTime>? seededAt,
  }) {
    return SeedStateCompanion(
      id: id ?? this.id,
      seedVersion: seedVersion ?? this.seedVersion,
      seededAt: seededAt ?? this.seededAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seedVersion.present) {
      map['seed_version'] = Variable<String>(seedVersion.value);
    }
    if (seededAt.present) {
      map['seeded_at'] = Variable<DateTime>(seededAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeedStateCompanion(')
          ..write('id: $id, ')
          ..write('seedVersion: $seedVersion, ')
          ..write('seededAt: $seededAt')
          ..write(')'))
        .toString();
  }
}

class $LocalPhotosTable extends LocalPhotos
    with TableInfo<$LocalPhotosTable, LocalPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteLengthMeta = const VerificationMeta(
    'byteLength',
  );
  @override
  late final GeneratedColumn<int> byteLength = GeneratedColumn<int>(
    'byte_length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cloudIdMeta = const VerificationMeta(
    'cloudId',
  );
  @override
  late final GeneratedColumn<String> cloudId = GeneratedColumn<String>(
    'cloud_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    farmId,
    relativePath,
    contentType,
    byteLength,
    cloudId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('byte_length')) {
      context.handle(
        _byteLengthMeta,
        byteLength.isAcceptableOrUnknown(data['byte_length']!, _byteLengthMeta),
      );
    } else if (isInserting) {
      context.missing(_byteLengthMeta);
    }
    if (data.containsKey('cloud_id')) {
      context.handle(
        _cloudIdMeta,
        cloudId.isAcceptableOrUnknown(data['cloud_id']!, _cloudIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPhoto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      byteLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_length'],
      )!,
      cloudId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_id'],
      ),
    );
  }

  @override
  $LocalPhotosTable createAlias(String alias) {
    return $LocalPhotosTable(attachedDatabase, alias);
  }
}

class LocalPhoto extends DataClass implements Insertable<LocalPhoto> {
  final String id;
  final String ownerId;
  final String farmId;
  final String relativePath;
  final String contentType;
  final int byteLength;
  final String? cloudId;
  const LocalPhoto({
    required this.id,
    required this.ownerId,
    required this.farmId,
    required this.relativePath,
    required this.contentType,
    required this.byteLength,
    this.cloudId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['farm_id'] = Variable<String>(farmId);
    map['relative_path'] = Variable<String>(relativePath);
    map['content_type'] = Variable<String>(contentType);
    map['byte_length'] = Variable<int>(byteLength);
    if (!nullToAbsent || cloudId != null) {
      map['cloud_id'] = Variable<String>(cloudId);
    }
    return map;
  }

  LocalPhotosCompanion toCompanion(bool nullToAbsent) {
    return LocalPhotosCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      farmId: Value(farmId),
      relativePath: Value(relativePath),
      contentType: Value(contentType),
      byteLength: Value(byteLength),
      cloudId: cloudId == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudId),
    );
  }

  factory LocalPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPhoto(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      farmId: serializer.fromJson<String>(json['farmId']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      contentType: serializer.fromJson<String>(json['contentType']),
      byteLength: serializer.fromJson<int>(json['byteLength']),
      cloudId: serializer.fromJson<String?>(json['cloudId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'farmId': serializer.toJson<String>(farmId),
      'relativePath': serializer.toJson<String>(relativePath),
      'contentType': serializer.toJson<String>(contentType),
      'byteLength': serializer.toJson<int>(byteLength),
      'cloudId': serializer.toJson<String?>(cloudId),
    };
  }

  LocalPhoto copyWith({
    String? id,
    String? ownerId,
    String? farmId,
    String? relativePath,
    String? contentType,
    int? byteLength,
    Value<String?> cloudId = const Value.absent(),
  }) => LocalPhoto(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    farmId: farmId ?? this.farmId,
    relativePath: relativePath ?? this.relativePath,
    contentType: contentType ?? this.contentType,
    byteLength: byteLength ?? this.byteLength,
    cloudId: cloudId.present ? cloudId.value : this.cloudId,
  );
  LocalPhoto copyWithCompanion(LocalPhotosCompanion data) {
    return LocalPhoto(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      byteLength: data.byteLength.present
          ? data.byteLength.value
          : this.byteLength,
      cloudId: data.cloudId.present ? data.cloudId.value : this.cloudId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPhoto(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('farmId: $farmId, ')
          ..write('relativePath: $relativePath, ')
          ..write('contentType: $contentType, ')
          ..write('byteLength: $byteLength, ')
          ..write('cloudId: $cloudId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    farmId,
    relativePath,
    contentType,
    byteLength,
    cloudId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPhoto &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.farmId == this.farmId &&
          other.relativePath == this.relativePath &&
          other.contentType == this.contentType &&
          other.byteLength == this.byteLength &&
          other.cloudId == this.cloudId);
}

class LocalPhotosCompanion extends UpdateCompanion<LocalPhoto> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> farmId;
  final Value<String> relativePath;
  final Value<String> contentType;
  final Value<int> byteLength;
  final Value<String?> cloudId;
  final Value<int> rowid;
  const LocalPhotosCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.farmId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.contentType = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.cloudId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPhotosCompanion.insert({
    required String id,
    required String ownerId,
    required String farmId,
    required String relativePath,
    required String contentType,
    required int byteLength,
    this.cloudId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       farmId = Value(farmId),
       relativePath = Value(relativePath),
       contentType = Value(contentType),
       byteLength = Value(byteLength);
  static Insertable<LocalPhoto> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? farmId,
    Expression<String>? relativePath,
    Expression<String>? contentType,
    Expression<int>? byteLength,
    Expression<String>? cloudId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (farmId != null) 'farm_id': farmId,
      if (relativePath != null) 'relative_path': relativePath,
      if (contentType != null) 'content_type': contentType,
      if (byteLength != null) 'byte_length': byteLength,
      if (cloudId != null) 'cloud_id': cloudId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? farmId,
    Value<String>? relativePath,
    Value<String>? contentType,
    Value<int>? byteLength,
    Value<String?>? cloudId,
    Value<int>? rowid,
  }) {
    return LocalPhotosCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      farmId: farmId ?? this.farmId,
      relativePath: relativePath ?? this.relativePath,
      contentType: contentType ?? this.contentType,
      byteLength: byteLength ?? this.byteLength,
      cloudId: cloudId ?? this.cloudId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (byteLength.present) {
      map['byte_length'] = Variable<int>(byteLength.value);
    }
    if (cloudId.present) {
      map['cloud_id'] = Variable<String>(cloudId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPhotosCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('farmId: $farmId, ')
          ..write('relativePath: $relativePath, ')
          ..write('contentType: $contentType, ')
          ..write('byteLength: $byteLength, ')
          ..write('cloudId: $cloudId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AlmanacDatabase extends GeneratedDatabase {
  _$AlmanacDatabase(QueryExecutor e) : super(e);
  $AlmanacDatabaseManager get managers => $AlmanacDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $FarmsTable farms = $FarmsTable(this);
  late final $SectionsTable sections = $SectionsTable(this);
  late final $PlantingsTable plantings = $PlantingsTable(this);
  late final $ObservationsTable observations = $ObservationsTable(this);
  late final $FarmTasksTable farmTasks = $FarmTasksTable(this);
  late final $FinancialRecordsTable financialRecords = $FinancialRecordsTable(
    this,
  );
  late final $SavedPlansTable savedPlans = $SavedPlansTable(this);
  late final $SectionProjectionsTable sectionProjections =
      $SectionProjectionsTable(this);
  late final $SectionDetailsTable sectionDetails = $SectionDetailsTable(this);
  late final $SyncMutationsTable syncMutations = $SyncMutationsTable(this);
  late final $SeedStateTable seedState = $SeedStateTable(this);
  late final $LocalPhotosTable localPhotos = $LocalPhotosTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    users,
    farms,
    sections,
    plantings,
    observations,
    farmTasks,
    financialRecords,
    savedPlans,
    sectionProjections,
    sectionDetails,
    syncMutations,
    seedState,
    localPhotos,
  ];
}

typedef $$UsersTableCreateCompanionBuilder = UsersCompanion Function({
  required String id,
  required String displayName,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$UsersTableUpdateCompanionBuilder = UsersCompanion Function({
  Value<String> id,
  Value<String> displayName,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$UsersTableFilterComposer
    extends Composer<_$AlmanacDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsersTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, BaseReferences<_$AlmanacDatabase, $UsersTable, User>),
          User,
          PrefetchHooks Function()
        > {
  $$UsersTableTableManager(_$AlmanacDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                id: id,
                displayName: displayName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                id: id,
                displayName: displayName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UsersTable, User>(table),
                  BaseReferences<_$AlmanacDatabase, $UsersTable, User>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, BaseReferences<_$AlmanacDatabase, $UsersTable, User>),
      User,
      PrefetchHooks Function()
    >;
typedef $$FarmsTableCreateCompanionBuilder = FarmsCompanion Function({
  required String id,
  required String farmId,
  required String ownerId,
  Value<int> version,
  Value<String> syncState,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  required String name,
  Value<String?> locality,
  Value<int> rowid,
});
typedef $$FarmsTableUpdateCompanionBuilder = FarmsCompanion Function({
  Value<String> id,
  Value<String> farmId,
  Value<String> ownerId,
  Value<int> version,
  Value<String> syncState,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<String> name,
  Value<String?> locality,
  Value<int> rowid,
});

class $$FarmsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $FarmsTable> {
  $$FarmsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locality => $composableBuilder(
    column: $table.locality,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FarmsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $FarmsTable> {
  $$FarmsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locality => $composableBuilder(
    column: $table.locality,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FarmsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $FarmsTable> {
  $$FarmsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get locality =>
      $composableBuilder(column: $table.locality, builder: (column) => column);
}

class $$FarmsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $FarmsTable,
          Farm,
          $$FarmsTableFilterComposer,
          $$FarmsTableOrderingComposer,
          $$FarmsTableAnnotationComposer,
          $$FarmsTableCreateCompanionBuilder,
          $$FarmsTableUpdateCompanionBuilder,
          (Farm, BaseReferences<_$AlmanacDatabase, $FarmsTable, Farm>),
          Farm,
          PrefetchHooks Function()
        > {
  $$FarmsTableTableManager(_$AlmanacDatabase db, $FarmsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FarmsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FarmsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FarmsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> locality = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmsCompanion(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                name: name,
                locality: locality,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String farmId,
                required String ownerId,
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String name,
                Value<String?> locality = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmsCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                name: name,
                locality: locality,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FarmsTable, Farm>(table),
                  BaseReferences<_$AlmanacDatabase, $FarmsTable, Farm>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FarmsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $FarmsTable,
      Farm,
      $$FarmsTableFilterComposer,
      $$FarmsTableOrderingComposer,
      $$FarmsTableAnnotationComposer,
      $$FarmsTableCreateCompanionBuilder,
      $$FarmsTableUpdateCompanionBuilder,
      (Farm, BaseReferences<_$AlmanacDatabase, $FarmsTable, Farm>),
      Farm,
      PrefetchHooks Function()
    >;
typedef $$SectionsTableCreateCompanionBuilder = SectionsCompanion Function({
  required String id,
  required String farmId,
  required String ownerId,
  Value<int> version,
  Value<String> syncState,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  required String name,
  Value<String?> boundary,
  Value<String?> areaM2,
  Value<String?> areaSource,
  Value<int> rowid,
});
typedef $$SectionsTableUpdateCompanionBuilder = SectionsCompanion Function({
  Value<String> id,
  Value<String> farmId,
  Value<String> ownerId,
  Value<int> version,
  Value<String> syncState,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<String> name,
  Value<String?> boundary,
  Value<String?> areaM2,
  Value<String?> areaSource,
  Value<int> rowid,
});

class $$SectionsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $SectionsTable> {
  $$SectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get boundary => $composableBuilder(
    column: $table.boundary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaM2 => $composableBuilder(
    column: $table.areaM2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaSource => $composableBuilder(
    column: $table.areaSource,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SectionsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $SectionsTable> {
  $$SectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get boundary => $composableBuilder(
    column: $table.boundary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaM2 => $composableBuilder(
    column: $table.areaM2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaSource => $composableBuilder(
    column: $table.areaSource,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SectionsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $SectionsTable> {
  $$SectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get boundary =>
      $composableBuilder(column: $table.boundary, builder: (column) => column);

  GeneratedColumn<String> get areaM2 =>
      $composableBuilder(column: $table.areaM2, builder: (column) => column);

  GeneratedColumn<String> get areaSource => $composableBuilder(
    column: $table.areaSource,
    builder: (column) => column,
  );
}

class $$SectionsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $SectionsTable,
          Section,
          $$SectionsTableFilterComposer,
          $$SectionsTableOrderingComposer,
          $$SectionsTableAnnotationComposer,
          $$SectionsTableCreateCompanionBuilder,
          $$SectionsTableUpdateCompanionBuilder,
          (Section, BaseReferences<_$AlmanacDatabase, $SectionsTable, Section>),
          Section,
          PrefetchHooks Function()
        > {
  $$SectionsTableTableManager(_$AlmanacDatabase db, $SectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> boundary = const Value.absent(),
                Value<String?> areaM2 = const Value.absent(),
                Value<String?> areaSource = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SectionsCompanion(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                name: name,
                boundary: boundary,
                areaM2: areaM2,
                areaSource: areaSource,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String farmId,
                required String ownerId,
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String name,
                Value<String?> boundary = const Value.absent(),
                Value<String?> areaM2 = const Value.absent(),
                Value<String?> areaSource = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SectionsCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                name: name,
                boundary: boundary,
                areaM2: areaM2,
                areaSource: areaSource,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SectionsTable, Section>(table),
                  BaseReferences<_$AlmanacDatabase, $SectionsTable, Section>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $SectionsTable,
      Section,
      $$SectionsTableFilterComposer,
      $$SectionsTableOrderingComposer,
      $$SectionsTableAnnotationComposer,
      $$SectionsTableCreateCompanionBuilder,
      $$SectionsTableUpdateCompanionBuilder,
      (Section, BaseReferences<_$AlmanacDatabase, $SectionsTable, Section>),
      Section,
      PrefetchHooks Function()
    >;
typedef $$PlantingsTableCreateCompanionBuilder = PlantingsCompanion Function({
  required String id,
  required String farmId,
  required String ownerId,
  Value<int> version,
  Value<String> syncState,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  required String sectionId,
  required String crop,
  Value<String?> variety,
  Value<DateTime?> plantedOn,
  Value<bool> isCurrent,
  Value<int> rowid,
});
typedef $$PlantingsTableUpdateCompanionBuilder = PlantingsCompanion Function({
  Value<String> id,
  Value<String> farmId,
  Value<String> ownerId,
  Value<int> version,
  Value<String> syncState,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<String> sectionId,
  Value<String> crop,
  Value<String?> variety,
  Value<DateTime?> plantedOn,
  Value<bool> isCurrent,
  Value<int> rowid,
});

class $$PlantingsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $PlantingsTable> {
  $$PlantingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get crop => $composableBuilder(
    column: $table.crop,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variety => $composableBuilder(
    column: $table.variety,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get plantedOn => $composableBuilder(
    column: $table.plantedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlantingsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $PlantingsTable> {
  $$PlantingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get crop => $composableBuilder(
    column: $table.crop,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variety => $composableBuilder(
    column: $table.variety,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get plantedOn => $composableBuilder(
    column: $table.plantedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlantingsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $PlantingsTable> {
  $$PlantingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get crop =>
      $composableBuilder(column: $table.crop, builder: (column) => column);

  GeneratedColumn<String> get variety =>
      $composableBuilder(column: $table.variety, builder: (column) => column);

  GeneratedColumn<DateTime> get plantedOn =>
      $composableBuilder(column: $table.plantedOn, builder: (column) => column);

  GeneratedColumn<bool> get isCurrent =>
      $composableBuilder(column: $table.isCurrent, builder: (column) => column);
}

class $$PlantingsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $PlantingsTable,
          Planting,
          $$PlantingsTableFilterComposer,
          $$PlantingsTableOrderingComposer,
          $$PlantingsTableAnnotationComposer,
          $$PlantingsTableCreateCompanionBuilder,
          $$PlantingsTableUpdateCompanionBuilder,
          (
            Planting,
            BaseReferences<_$AlmanacDatabase, $PlantingsTable, Planting>,
          ),
          Planting,
          PrefetchHooks Function()
        > {
  $$PlantingsTableTableManager(_$AlmanacDatabase db, $PlantingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlantingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlantingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlantingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<String> crop = const Value.absent(),
                Value<String?> variety = const Value.absent(),
                Value<DateTime?> plantedOn = const Value.absent(),
                Value<bool> isCurrent = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlantingsCompanion(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                crop: crop,
                variety: variety,
                plantedOn: plantedOn,
                isCurrent: isCurrent,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String farmId,
                required String ownerId,
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String sectionId,
                required String crop,
                Value<String?> variety = const Value.absent(),
                Value<DateTime?> plantedOn = const Value.absent(),
                Value<bool> isCurrent = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlantingsCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                crop: crop,
                variety: variety,
                plantedOn: plantedOn,
                isCurrent: isCurrent,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlantingsTable, Planting>(table),
                  BaseReferences<_$AlmanacDatabase, $PlantingsTable, Planting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlantingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $PlantingsTable,
      Planting,
      $$PlantingsTableFilterComposer,
      $$PlantingsTableOrderingComposer,
      $$PlantingsTableAnnotationComposer,
      $$PlantingsTableCreateCompanionBuilder,
      $$PlantingsTableUpdateCompanionBuilder,
      (Planting, BaseReferences<_$AlmanacDatabase, $PlantingsTable, Planting>),
      Planting,
      PrefetchHooks Function()
    >;
typedef $$ObservationsTableCreateCompanionBuilder =
    ObservationsCompanion Function({
      required String id,
      required String farmId,
      required String ownerId,
      Value<int> version,
      Value<String> syncState,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String sectionId,
      required String type,
      required String note,
      Value<String?> healthStatus,
      Value<String?> actionTaken,
      Value<String?> localMediaId,
      Value<bool> createdByVoice,
      Value<int?> healthScore,
      Value<int> rowid,
    });
typedef $$ObservationsTableUpdateCompanionBuilder =
    ObservationsCompanion Function({
      Value<String> id,
      Value<String> farmId,
      Value<String> ownerId,
      Value<int> version,
      Value<String> syncState,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> sectionId,
      Value<String> type,
      Value<String> note,
      Value<String?> healthStatus,
      Value<String?> actionTaken,
      Value<String?> localMediaId,
      Value<bool> createdByVoice,
      Value<int?> healthScore,
      Value<int> rowid,
    });

class $$ObservationsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $ObservationsTable> {
  $$ObservationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get healthStatus => $composableBuilder(
    column: $table.healthStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionTaken => $composableBuilder(
    column: $table.actionTaken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localMediaId => $composableBuilder(
    column: $table.localMediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get createdByVoice => $composableBuilder(
    column: $table.createdByVoice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get healthScore => $composableBuilder(
    column: $table.healthScore,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ObservationsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $ObservationsTable> {
  $$ObservationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get healthStatus => $composableBuilder(
    column: $table.healthStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionTaken => $composableBuilder(
    column: $table.actionTaken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localMediaId => $composableBuilder(
    column: $table.localMediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get createdByVoice => $composableBuilder(
    column: $table.createdByVoice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get healthScore => $composableBuilder(
    column: $table.healthScore,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ObservationsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $ObservationsTable> {
  $$ObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get healthStatus => $composableBuilder(
    column: $table.healthStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actionTaken => $composableBuilder(
    column: $table.actionTaken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localMediaId => $composableBuilder(
    column: $table.localMediaId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get createdByVoice => $composableBuilder(
    column: $table.createdByVoice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get healthScore => $composableBuilder(
    column: $table.healthScore,
    builder: (column) => column,
  );
}

class $$ObservationsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $ObservationsTable,
          Observation,
          $$ObservationsTableFilterComposer,
          $$ObservationsTableOrderingComposer,
          $$ObservationsTableAnnotationComposer,
          $$ObservationsTableCreateCompanionBuilder,
          $$ObservationsTableUpdateCompanionBuilder,
          (
            Observation,
            BaseReferences<_$AlmanacDatabase, $ObservationsTable, Observation>,
          ),
          Observation,
          PrefetchHooks Function()
        > {
  $$ObservationsTableTableManager(
    _$AlmanacDatabase db,
    $ObservationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObservationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObservationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> healthStatus = const Value.absent(),
                Value<String?> actionTaken = const Value.absent(),
                Value<String?> localMediaId = const Value.absent(),
                Value<bool> createdByVoice = const Value.absent(),
                Value<int?> healthScore = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                type: type,
                note: note,
                healthStatus: healthStatus,
                actionTaken: actionTaken,
                localMediaId: localMediaId,
                createdByVoice: createdByVoice,
                healthScore: healthScore,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String farmId,
                required String ownerId,
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String sectionId,
                required String type,
                required String note,
                Value<String?> healthStatus = const Value.absent(),
                Value<String?> actionTaken = const Value.absent(),
                Value<String?> localMediaId = const Value.absent(),
                Value<bool> createdByVoice = const Value.absent(),
                Value<int?> healthScore = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                type: type,
                note: note,
                healthStatus: healthStatus,
                actionTaken: actionTaken,
                localMediaId: localMediaId,
                createdByVoice: createdByVoice,
                healthScore: healthScore,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ObservationsTable, Observation>(table),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $ObservationsTable,
                    Observation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $ObservationsTable,
      Observation,
      $$ObservationsTableFilterComposer,
      $$ObservationsTableOrderingComposer,
      $$ObservationsTableAnnotationComposer,
      $$ObservationsTableCreateCompanionBuilder,
      $$ObservationsTableUpdateCompanionBuilder,
      (
        Observation,
        BaseReferences<_$AlmanacDatabase, $ObservationsTable, Observation>,
      ),
      Observation,
      PrefetchHooks Function()
    >;
typedef $$FarmTasksTableCreateCompanionBuilder = FarmTasksCompanion Function({
  required String id,
  required String farmId,
  required String ownerId,
  Value<int> version,
  Value<String> syncState,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  required String sectionId,
  required String title,
  Value<String?> description,
  required DateTime dueDate,
  Value<String> status,
  Value<int?> expectedCostCents,
  Value<String?> planId,
  Value<int> rowid,
});
typedef $$FarmTasksTableUpdateCompanionBuilder = FarmTasksCompanion Function({
  Value<String> id,
  Value<String> farmId,
  Value<String> ownerId,
  Value<int> version,
  Value<String> syncState,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<String> sectionId,
  Value<String> title,
  Value<String?> description,
  Value<DateTime> dueDate,
  Value<String> status,
  Value<int?> expectedCostCents,
  Value<String?> planId,
  Value<int> rowid,
});

class $$FarmTasksTableFilterComposer
    extends Composer<_$AlmanacDatabase, $FarmTasksTable> {
  $$FarmTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedCostCents => $composableBuilder(
    column: $table.expectedCostCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FarmTasksTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $FarmTasksTable> {
  $$FarmTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedCostCents => $composableBuilder(
    column: $table.expectedCostCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FarmTasksTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $FarmTasksTable> {
  $$FarmTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get expectedCostCents => $composableBuilder(
    column: $table.expectedCostCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);
}

class $$FarmTasksTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $FarmTasksTable,
          FarmTask,
          $$FarmTasksTableFilterComposer,
          $$FarmTasksTableOrderingComposer,
          $$FarmTasksTableAnnotationComposer,
          $$FarmTasksTableCreateCompanionBuilder,
          $$FarmTasksTableUpdateCompanionBuilder,
          (
            FarmTask,
            BaseReferences<_$AlmanacDatabase, $FarmTasksTable, FarmTask>,
          ),
          FarmTask,
          PrefetchHooks Function()
        > {
  $$FarmTasksTableTableManager(_$AlmanacDatabase db, $FarmTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FarmTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FarmTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FarmTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> dueDate = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> expectedCostCents = const Value.absent(),
                Value<String?> planId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmTasksCompanion(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                title: title,
                description: description,
                dueDate: dueDate,
                status: status,
                expectedCostCents: expectedCostCents,
                planId: planId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String farmId,
                required String ownerId,
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String sectionId,
                required String title,
                Value<String?> description = const Value.absent(),
                required DateTime dueDate,
                Value<String> status = const Value.absent(),
                Value<int?> expectedCostCents = const Value.absent(),
                Value<String?> planId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmTasksCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                title: title,
                description: description,
                dueDate: dueDate,
                status: status,
                expectedCostCents: expectedCostCents,
                planId: planId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FarmTasksTable, FarmTask>(table),
                  BaseReferences<_$AlmanacDatabase, $FarmTasksTable, FarmTask>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FarmTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $FarmTasksTable,
      FarmTask,
      $$FarmTasksTableFilterComposer,
      $$FarmTasksTableOrderingComposer,
      $$FarmTasksTableAnnotationComposer,
      $$FarmTasksTableCreateCompanionBuilder,
      $$FarmTasksTableUpdateCompanionBuilder,
      (FarmTask, BaseReferences<_$AlmanacDatabase, $FarmTasksTable, FarmTask>),
      FarmTask,
      PrefetchHooks Function()
    >;
typedef $$FinancialRecordsTableCreateCompanionBuilder =
    FinancialRecordsCompanion Function({
      required String id,
      required String farmId,
      required String ownerId,
      Value<int> version,
      Value<String> syncState,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> sectionId,
      required String type,
      required String category,
      required int amountCents,
      required DateTime date,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$FinancialRecordsTableUpdateCompanionBuilder =
    FinancialRecordsCompanion Function({
      Value<String> id,
      Value<String> farmId,
      Value<String> ownerId,
      Value<int> version,
      Value<String> syncState,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> sectionId,
      Value<String> type,
      Value<String> category,
      Value<int> amountCents,
      Value<DateTime> date,
      Value<String?> note,
      Value<int> rowid,
    });

class $$FinancialRecordsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $FinancialRecordsTable> {
  $$FinancialRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FinancialRecordsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $FinancialRecordsTable> {
  $$FinancialRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FinancialRecordsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $FinancialRecordsTable> {
  $$FinancialRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$FinancialRecordsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $FinancialRecordsTable,
          FinancialRecord,
          $$FinancialRecordsTableFilterComposer,
          $$FinancialRecordsTableOrderingComposer,
          $$FinancialRecordsTableAnnotationComposer,
          $$FinancialRecordsTableCreateCompanionBuilder,
          $$FinancialRecordsTableUpdateCompanionBuilder,
          (
            FinancialRecord,
            BaseReferences<
              _$AlmanacDatabase,
              $FinancialRecordsTable,
              FinancialRecord
            >,
          ),
          FinancialRecord,
          PrefetchHooks Function()
        > {
  $$FinancialRecordsTableTableManager(
    _$AlmanacDatabase db,
    $FinancialRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FinancialRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FinancialRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FinancialRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> sectionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FinancialRecordsCompanion(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                type: type,
                category: category,
                amountCents: amountCents,
                date: date,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String farmId,
                required String ownerId,
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> sectionId = const Value.absent(),
                required String type,
                required String category,
                required int amountCents,
                required DateTime date,
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FinancialRecordsCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                type: type,
                category: category,
                amountCents: amountCents,
                date: date,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FinancialRecordsTable, FinancialRecord>(table),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $FinancialRecordsTable,
                    FinancialRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FinancialRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $FinancialRecordsTable,
      FinancialRecord,
      $$FinancialRecordsTableFilterComposer,
      $$FinancialRecordsTableOrderingComposer,
      $$FinancialRecordsTableAnnotationComposer,
      $$FinancialRecordsTableCreateCompanionBuilder,
      $$FinancialRecordsTableUpdateCompanionBuilder,
      (
        FinancialRecord,
        BaseReferences<
          _$AlmanacDatabase,
          $FinancialRecordsTable,
          FinancialRecord
        >,
      ),
      FinancialRecord,
      PrefetchHooks Function()
    >;
typedef $$SavedPlansTableCreateCompanionBuilder = SavedPlansCompanion Function({
  required String id,
  required String farmId,
  required String ownerId,
  Value<int> version,
  Value<String> syncState,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  required String sectionId,
  Value<String> status,
  required String plan,
  Value<DateTime?> approvedAt,
  Value<int> rowid,
});
typedef $$SavedPlansTableUpdateCompanionBuilder = SavedPlansCompanion Function({
  Value<String> id,
  Value<String> farmId,
  Value<String> ownerId,
  Value<int> version,
  Value<String> syncState,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<String> sectionId,
  Value<String> status,
  Value<String> plan,
  Value<DateTime?> approvedAt,
  Value<int> rowid,
});

class $$SavedPlansTableFilterComposer
    extends Composer<_$AlmanacDatabase, $SavedPlansTable> {
  $$SavedPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plan => $composableBuilder(
    column: $table.plan,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get approvedAt => $composableBuilder(
    column: $table.approvedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedPlansTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $SavedPlansTable> {
  $$SavedPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plan => $composableBuilder(
    column: $table.plan,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get approvedAt => $composableBuilder(
    column: $table.approvedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedPlansTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $SavedPlansTable> {
  $$SavedPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get plan =>
      $composableBuilder(column: $table.plan, builder: (column) => column);

  GeneratedColumn<DateTime> get approvedAt => $composableBuilder(
    column: $table.approvedAt,
    builder: (column) => column,
  );
}

class $$SavedPlansTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $SavedPlansTable,
          SavedPlan,
          $$SavedPlansTableFilterComposer,
          $$SavedPlansTableOrderingComposer,
          $$SavedPlansTableAnnotationComposer,
          $$SavedPlansTableCreateCompanionBuilder,
          $$SavedPlansTableUpdateCompanionBuilder,
          (
            SavedPlan,
            BaseReferences<_$AlmanacDatabase, $SavedPlansTable, SavedPlan>,
          ),
          SavedPlan,
          PrefetchHooks Function()
        > {
  $$SavedPlansTableTableManager(_$AlmanacDatabase db, $SavedPlansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> plan = const Value.absent(),
                Value<DateTime?> approvedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedPlansCompanion(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                status: status,
                plan: plan,
                approvedAt: approvedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String farmId,
                required String ownerId,
                Value<int> version = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String sectionId,
                Value<String> status = const Value.absent(),
                required String plan,
                Value<DateTime?> approvedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedPlansCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                version: version,
                syncState: syncState,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                sectionId: sectionId,
                status: status,
                plan: plan,
                approvedAt: approvedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavedPlansTable, SavedPlan>(table),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $SavedPlansTable,
                    SavedPlan
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $SavedPlansTable,
      SavedPlan,
      $$SavedPlansTableFilterComposer,
      $$SavedPlansTableOrderingComposer,
      $$SavedPlansTableAnnotationComposer,
      $$SavedPlansTableCreateCompanionBuilder,
      $$SavedPlansTableUpdateCompanionBuilder,
      (
        SavedPlan,
        BaseReferences<_$AlmanacDatabase, $SavedPlansTable, SavedPlan>,
      ),
      SavedPlan,
      PrefetchHooks Function()
    >;
typedef $$SectionProjectionsTableCreateCompanionBuilder =
    SectionProjectionsCompanion Function({
      required String sectionId,
      required int expectedProfitCents,
      required int expectedCostCents,
      required DateTime harvestStart,
      required DateTime harvestEnd,
      Value<String?> planId,
      Value<int> rowid,
    });
typedef $$SectionProjectionsTableUpdateCompanionBuilder =
    SectionProjectionsCompanion Function({
      Value<String> sectionId,
      Value<int> expectedProfitCents,
      Value<int> expectedCostCents,
      Value<DateTime> harvestStart,
      Value<DateTime> harvestEnd,
      Value<String?> planId,
      Value<int> rowid,
    });

class $$SectionProjectionsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $SectionProjectionsTable> {
  $$SectionProjectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedProfitCents => $composableBuilder(
    column: $table.expectedProfitCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedCostCents => $composableBuilder(
    column: $table.expectedCostCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get harvestStart => $composableBuilder(
    column: $table.harvestStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get harvestEnd => $composableBuilder(
    column: $table.harvestEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SectionProjectionsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $SectionProjectionsTable> {
  $$SectionProjectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedProfitCents => $composableBuilder(
    column: $table.expectedProfitCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedCostCents => $composableBuilder(
    column: $table.expectedCostCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get harvestStart => $composableBuilder(
    column: $table.harvestStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get harvestEnd => $composableBuilder(
    column: $table.harvestEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SectionProjectionsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $SectionProjectionsTable> {
  $$SectionProjectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<int> get expectedProfitCents => $composableBuilder(
    column: $table.expectedProfitCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedCostCents => $composableBuilder(
    column: $table.expectedCostCents,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get harvestStart => $composableBuilder(
    column: $table.harvestStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get harvestEnd => $composableBuilder(
    column: $table.harvestEnd,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);
}

class $$SectionProjectionsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $SectionProjectionsTable,
          SectionProjection,
          $$SectionProjectionsTableFilterComposer,
          $$SectionProjectionsTableOrderingComposer,
          $$SectionProjectionsTableAnnotationComposer,
          $$SectionProjectionsTableCreateCompanionBuilder,
          $$SectionProjectionsTableUpdateCompanionBuilder,
          (
            SectionProjection,
            BaseReferences<
              _$AlmanacDatabase,
              $SectionProjectionsTable,
              SectionProjection
            >,
          ),
          SectionProjection,
          PrefetchHooks Function()
        > {
  $$SectionProjectionsTableTableManager(
    _$AlmanacDatabase db,
    $SectionProjectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SectionProjectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SectionProjectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SectionProjectionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sectionId = const Value.absent(),
                Value<int> expectedProfitCents = const Value.absent(),
                Value<int> expectedCostCents = const Value.absent(),
                Value<DateTime> harvestStart = const Value.absent(),
                Value<DateTime> harvestEnd = const Value.absent(),
                Value<String?> planId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SectionProjectionsCompanion(
                sectionId: sectionId,
                expectedProfitCents: expectedProfitCents,
                expectedCostCents: expectedCostCents,
                harvestStart: harvestStart,
                harvestEnd: harvestEnd,
                planId: planId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sectionId,
                required int expectedProfitCents,
                required int expectedCostCents,
                required DateTime harvestStart,
                required DateTime harvestEnd,
                Value<String?> planId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SectionProjectionsCompanion.insert(
                sectionId: sectionId,
                expectedProfitCents: expectedProfitCents,
                expectedCostCents: expectedCostCents,
                harvestStart: harvestStart,
                harvestEnd: harvestEnd,
                planId: planId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SectionProjectionsTable, SectionProjection>(
                    table,
                  ),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $SectionProjectionsTable,
                    SectionProjection
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SectionProjectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $SectionProjectionsTable,
      SectionProjection,
      $$SectionProjectionsTableFilterComposer,
      $$SectionProjectionsTableOrderingComposer,
      $$SectionProjectionsTableAnnotationComposer,
      $$SectionProjectionsTableCreateCompanionBuilder,
      $$SectionProjectionsTableUpdateCompanionBuilder,
      (
        SectionProjection,
        BaseReferences<
          _$AlmanacDatabase,
          $SectionProjectionsTable,
          SectionProjection
        >,
      ),
      SectionProjection,
      PrefetchHooks Function()
    >;
typedef $$SectionDetailsTableCreateCompanionBuilder =
    SectionDetailsCompanion Function({
      required String sectionId,
      Value<String?> description,
      Value<String?> waterNote,
      Value<String?> soilNote,
      Value<String?> marketNote,
      Value<int> rowid,
    });
typedef $$SectionDetailsTableUpdateCompanionBuilder =
    SectionDetailsCompanion Function({
      Value<String> sectionId,
      Value<String?> description,
      Value<String?> waterNote,
      Value<String?> soilNote,
      Value<String?> marketNote,
      Value<int> rowid,
    });

class $$SectionDetailsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $SectionDetailsTable> {
  $$SectionDetailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waterNote => $composableBuilder(
    column: $table.waterNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get soilNote => $composableBuilder(
    column: $table.soilNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get marketNote => $composableBuilder(
    column: $table.marketNote,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SectionDetailsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $SectionDetailsTable> {
  $$SectionDetailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waterNote => $composableBuilder(
    column: $table.waterNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get soilNote => $composableBuilder(
    column: $table.soilNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get marketNote => $composableBuilder(
    column: $table.marketNote,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SectionDetailsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $SectionDetailsTable> {
  $$SectionDetailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get waterNote =>
      $composableBuilder(column: $table.waterNote, builder: (column) => column);

  GeneratedColumn<String> get soilNote =>
      $composableBuilder(column: $table.soilNote, builder: (column) => column);

  GeneratedColumn<String> get marketNote => $composableBuilder(
    column: $table.marketNote,
    builder: (column) => column,
  );
}

class $$SectionDetailsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $SectionDetailsTable,
          SectionDetail,
          $$SectionDetailsTableFilterComposer,
          $$SectionDetailsTableOrderingComposer,
          $$SectionDetailsTableAnnotationComposer,
          $$SectionDetailsTableCreateCompanionBuilder,
          $$SectionDetailsTableUpdateCompanionBuilder,
          (
            SectionDetail,
            BaseReferences<
              _$AlmanacDatabase,
              $SectionDetailsTable,
              SectionDetail
            >,
          ),
          SectionDetail,
          PrefetchHooks Function()
        > {
  $$SectionDetailsTableTableManager(
    _$AlmanacDatabase db,
    $SectionDetailsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SectionDetailsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SectionDetailsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SectionDetailsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sectionId = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> waterNote = const Value.absent(),
                Value<String?> soilNote = const Value.absent(),
                Value<String?> marketNote = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SectionDetailsCompanion(
                sectionId: sectionId,
                description: description,
                waterNote: waterNote,
                soilNote: soilNote,
                marketNote: marketNote,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sectionId,
                Value<String?> description = const Value.absent(),
                Value<String?> waterNote = const Value.absent(),
                Value<String?> soilNote = const Value.absent(),
                Value<String?> marketNote = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SectionDetailsCompanion.insert(
                sectionId: sectionId,
                description: description,
                waterNote: waterNote,
                soilNote: soilNote,
                marketNote: marketNote,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SectionDetailsTable, SectionDetail>(table),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $SectionDetailsTable,
                    SectionDetail
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SectionDetailsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $SectionDetailsTable,
      SectionDetail,
      $$SectionDetailsTableFilterComposer,
      $$SectionDetailsTableOrderingComposer,
      $$SectionDetailsTableAnnotationComposer,
      $$SectionDetailsTableCreateCompanionBuilder,
      $$SectionDetailsTableUpdateCompanionBuilder,
      (
        SectionDetail,
        BaseReferences<_$AlmanacDatabase, $SectionDetailsTable, SectionDetail>,
      ),
      SectionDetail,
      PrefetchHooks Function()
    >;
typedef $$SyncMutationsTableCreateCompanionBuilder =
    SyncMutationsCompanion Function({
      required String mutationId,
      required String farmId,
      required String ownerId,
      required String operation,
      required String recordType,
      required String recordId,
      required DateTime createdAt,
      Value<DateTime?> syncedAt,
      Value<String?> payload,
      Value<int?> recordVersion,
      Value<String?> dependencyId,
      Value<String> deliveryState,
      Value<int> attemptCount,
      Value<int> budgetCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> errorCode,
      Value<int> rowid,
    });
typedef $$SyncMutationsTableUpdateCompanionBuilder =
    SyncMutationsCompanion Function({
      Value<String> mutationId,
      Value<String> farmId,
      Value<String> ownerId,
      Value<String> operation,
      Value<String> recordType,
      Value<String> recordId,
      Value<DateTime> createdAt,
      Value<DateTime?> syncedAt,
      Value<String?> payload,
      Value<int?> recordVersion,
      Value<String?> dependencyId,
      Value<String> deliveryState,
      Value<int> attemptCount,
      Value<int> budgetCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> errorCode,
      Value<int> rowid,
    });

class $$SyncMutationsTableFilterComposer
    extends Composer<_$AlmanacDatabase, $SyncMutationsTable> {
  $$SyncMutationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordVersion => $composableBuilder(
    column: $table.recordVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dependencyId => $composableBuilder(
    column: $table.dependencyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get budgetCount => $composableBuilder(
    column: $table.budgetCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMutationsTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $SyncMutationsTable> {
  $$SyncMutationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordVersion => $composableBuilder(
    column: $table.recordVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependencyId => $composableBuilder(
    column: $table.dependencyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get budgetCount => $composableBuilder(
    column: $table.budgetCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMutationsTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $SyncMutationsTable> {
  $$SyncMutationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get recordVersion => $composableBuilder(
    column: $table.recordVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dependencyId => $composableBuilder(
    column: $table.dependencyId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get budgetCount => $composableBuilder(
    column: $table.budgetCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);
}

class $$SyncMutationsTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $SyncMutationsTable,
          SyncMutation,
          $$SyncMutationsTableFilterComposer,
          $$SyncMutationsTableOrderingComposer,
          $$SyncMutationsTableAnnotationComposer,
          $$SyncMutationsTableCreateCompanionBuilder,
          $$SyncMutationsTableUpdateCompanionBuilder,
          (
            SyncMutation,
            BaseReferences<
              _$AlmanacDatabase,
              $SyncMutationsTable,
              SyncMutation
            >,
          ),
          SyncMutation,
          PrefetchHooks Function()
        > {
  $$SyncMutationsTableTableManager(
    _$AlmanacDatabase db,
    $SyncMutationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMutationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMutationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMutationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mutationId = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> recordType = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<int?> recordVersion = const Value.absent(),
                Value<String?> dependencyId = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> budgetCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMutationsCompanion(
                mutationId: mutationId,
                farmId: farmId,
                ownerId: ownerId,
                operation: operation,
                recordType: recordType,
                recordId: recordId,
                createdAt: createdAt,
                syncedAt: syncedAt,
                payload: payload,
                recordVersion: recordVersion,
                dependencyId: dependencyId,
                deliveryState: deliveryState,
                attemptCount: attemptCount,
                budgetCount: budgetCount,
                nextAttemptAt: nextAttemptAt,
                errorCode: errorCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mutationId,
                required String farmId,
                required String ownerId,
                required String operation,
                required String recordType,
                required String recordId,
                required DateTime createdAt,
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<int?> recordVersion = const Value.absent(),
                Value<String?> dependencyId = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> budgetCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMutationsCompanion.insert(
                mutationId: mutationId,
                farmId: farmId,
                ownerId: ownerId,
                operation: operation,
                recordType: recordType,
                recordId: recordId,
                createdAt: createdAt,
                syncedAt: syncedAt,
                payload: payload,
                recordVersion: recordVersion,
                dependencyId: dependencyId,
                deliveryState: deliveryState,
                attemptCount: attemptCount,
                budgetCount: budgetCount,
                nextAttemptAt: nextAttemptAt,
                errorCode: errorCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMutationsTable, SyncMutation>(table),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $SyncMutationsTable,
                    SyncMutation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMutationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $SyncMutationsTable,
      SyncMutation,
      $$SyncMutationsTableFilterComposer,
      $$SyncMutationsTableOrderingComposer,
      $$SyncMutationsTableAnnotationComposer,
      $$SyncMutationsTableCreateCompanionBuilder,
      $$SyncMutationsTableUpdateCompanionBuilder,
      (
        SyncMutation,
        BaseReferences<_$AlmanacDatabase, $SyncMutationsTable, SyncMutation>,
      ),
      SyncMutation,
      PrefetchHooks Function()
    >;
typedef $$SeedStateTableCreateCompanionBuilder = SeedStateCompanion Function({
  Value<int> id,
  required String seedVersion,
  required DateTime seededAt,
});
typedef $$SeedStateTableUpdateCompanionBuilder = SeedStateCompanion Function({
  Value<int> id,
  Value<String> seedVersion,
  Value<DateTime> seededAt,
});

class $$SeedStateTableFilterComposer
    extends Composer<_$AlmanacDatabase, $SeedStateTable> {
  $$SeedStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seedVersion => $composableBuilder(
    column: $table.seedVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get seededAt => $composableBuilder(
    column: $table.seededAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeedStateTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $SeedStateTable> {
  $$SeedStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seedVersion => $composableBuilder(
    column: $table.seedVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get seededAt => $composableBuilder(
    column: $table.seededAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeedStateTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $SeedStateTable> {
  $$SeedStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seedVersion => $composableBuilder(
    column: $table.seedVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get seededAt =>
      $composableBuilder(column: $table.seededAt, builder: (column) => column);
}

class $$SeedStateTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $SeedStateTable,
          SeedStateData,
          $$SeedStateTableFilterComposer,
          $$SeedStateTableOrderingComposer,
          $$SeedStateTableAnnotationComposer,
          $$SeedStateTableCreateCompanionBuilder,
          $$SeedStateTableUpdateCompanionBuilder,
          (
            SeedStateData,
            BaseReferences<_$AlmanacDatabase, $SeedStateTable, SeedStateData>,
          ),
          SeedStateData,
          PrefetchHooks Function()
        > {
  $$SeedStateTableTableManager(_$AlmanacDatabase db, $SeedStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeedStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeedStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeedStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> seedVersion = const Value.absent(),
                Value<DateTime> seededAt = const Value.absent(),
              }) => SeedStateCompanion(
                id: id,
                seedVersion: seedVersion,
                seededAt: seededAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String seedVersion,
                required DateTime seededAt,
              }) => SeedStateCompanion.insert(
                id: id,
                seedVersion: seedVersion,
                seededAt: seededAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SeedStateTable, SeedStateData>(table),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $SeedStateTable,
                    SeedStateData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeedStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $SeedStateTable,
      SeedStateData,
      $$SeedStateTableFilterComposer,
      $$SeedStateTableOrderingComposer,
      $$SeedStateTableAnnotationComposer,
      $$SeedStateTableCreateCompanionBuilder,
      $$SeedStateTableUpdateCompanionBuilder,
      (
        SeedStateData,
        BaseReferences<_$AlmanacDatabase, $SeedStateTable, SeedStateData>,
      ),
      SeedStateData,
      PrefetchHooks Function()
    >;
typedef $$LocalPhotosTableCreateCompanionBuilder =
    LocalPhotosCompanion Function({
      required String id,
      required String ownerId,
      required String farmId,
      required String relativePath,
      required String contentType,
      required int byteLength,
      Value<String?> cloudId,
      Value<int> rowid,
    });
typedef $$LocalPhotosTableUpdateCompanionBuilder =
    LocalPhotosCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> farmId,
      Value<String> relativePath,
      Value<String> contentType,
      Value<int> byteLength,
      Value<String?> cloudId,
      Value<int> rowid,
    });

class $$LocalPhotosTableFilterComposer
    extends Composer<_$AlmanacDatabase, $LocalPhotosTable> {
  $$LocalPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPhotosTableOrderingComposer
    extends Composer<_$AlmanacDatabase, $LocalPhotosTable> {
  $$LocalPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPhotosTableAnnotationComposer
    extends Composer<_$AlmanacDatabase, $LocalPhotosTable> {
  $$LocalPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudId =>
      $composableBuilder(column: $table.cloudId, builder: (column) => column);
}

class $$LocalPhotosTableTableManager
    extends
        RootTableManager<
          _$AlmanacDatabase,
          $LocalPhotosTable,
          LocalPhoto,
          $$LocalPhotosTableFilterComposer,
          $$LocalPhotosTableOrderingComposer,
          $$LocalPhotosTableAnnotationComposer,
          $$LocalPhotosTableCreateCompanionBuilder,
          $$LocalPhotosTableUpdateCompanionBuilder,
          (
            LocalPhoto,
            BaseReferences<_$AlmanacDatabase, $LocalPhotosTable, LocalPhoto>,
          ),
          LocalPhoto,
          PrefetchHooks Function()
        > {
  $$LocalPhotosTableTableManager(_$AlmanacDatabase db, $LocalPhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<int> byteLength = const Value.absent(),
                Value<String?> cloudId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPhotosCompanion(
                id: id,
                ownerId: ownerId,
                farmId: farmId,
                relativePath: relativePath,
                contentType: contentType,
                byteLength: byteLength,
                cloudId: cloudId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String farmId,
                required String relativePath,
                required String contentType,
                required int byteLength,
                Value<String?> cloudId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPhotosCompanion.insert(
                id: id,
                ownerId: ownerId,
                farmId: farmId,
                relativePath: relativePath,
                contentType: contentType,
                byteLength: byteLength,
                cloudId: cloudId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalPhotosTable, LocalPhoto>(table),
                  BaseReferences<
                    _$AlmanacDatabase,
                    $LocalPhotosTable,
                    LocalPhoto
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AlmanacDatabase,
      $LocalPhotosTable,
      LocalPhoto,
      $$LocalPhotosTableFilterComposer,
      $$LocalPhotosTableOrderingComposer,
      $$LocalPhotosTableAnnotationComposer,
      $$LocalPhotosTableCreateCompanionBuilder,
      $$LocalPhotosTableUpdateCompanionBuilder,
      (
        LocalPhoto,
        BaseReferences<_$AlmanacDatabase, $LocalPhotosTable, LocalPhoto>,
      ),
      LocalPhoto,
      PrefetchHooks Function()
    >;

class $AlmanacDatabaseManager {
  final _$AlmanacDatabase _db;
  $AlmanacDatabaseManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$FarmsTableTableManager get farms =>
      $$FarmsTableTableManager(_db, _db.farms);
  $$SectionsTableTableManager get sections =>
      $$SectionsTableTableManager(_db, _db.sections);
  $$PlantingsTableTableManager get plantings =>
      $$PlantingsTableTableManager(_db, _db.plantings);
  $$ObservationsTableTableManager get observations =>
      $$ObservationsTableTableManager(_db, _db.observations);
  $$FarmTasksTableTableManager get farmTasks =>
      $$FarmTasksTableTableManager(_db, _db.farmTasks);
  $$FinancialRecordsTableTableManager get financialRecords =>
      $$FinancialRecordsTableTableManager(_db, _db.financialRecords);
  $$SavedPlansTableTableManager get savedPlans =>
      $$SavedPlansTableTableManager(_db, _db.savedPlans);
  $$SectionProjectionsTableTableManager get sectionProjections =>
      $$SectionProjectionsTableTableManager(_db, _db.sectionProjections);
  $$SectionDetailsTableTableManager get sectionDetails =>
      $$SectionDetailsTableTableManager(_db, _db.sectionDetails);
  $$SyncMutationsTableTableManager get syncMutations =>
      $$SyncMutationsTableTableManager(_db, _db.syncMutations);
  $$SeedStateTableTableManager get seedState =>
      $$SeedStateTableTableManager(_db, _db.seedState);
  $$LocalPhotosTableTableManager get localPhotos =>
      $$LocalPhotosTableTableManager(_db, _db.localPhotos);
}
