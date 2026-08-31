// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, DbUser> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _pinMeta = const VerificationMeta('pin');
  @override
  late final GeneratedColumn<int> pin = GeneratedColumn<int>(
    'pin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _changeQuantityRightMeta =
      const VerificationMeta('changeQuantityRight');
  @override
  late final GeneratedColumn<bool> changeQuantityRight = GeneratedColumn<bool>(
    'change_quantity_right',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("change_quantity_right" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _allTablesOpenRightMeta =
      const VerificationMeta('allTablesOpenRight');
  @override
  late final GeneratedColumn<bool> allTablesOpenRight = GeneratedColumn<bool>(
    'all_tables_open_right',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_tables_open_right" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deleteRightMeta = const VerificationMeta(
    'deleteRight',
  );
  @override
  late final GeneratedColumn<bool> deleteRight = GeneratedColumn<bool>(
    'delete_right',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("delete_right" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _superuserMeta = const VerificationMeta(
    'superuser',
  );
  @override
  late final GeneratedColumn<bool> superuser = GeneratedColumn<bool>(
    'superuser',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("superuser" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    code,
    username,
    pin,
    changeQuantityRight,
    allTablesOpenRight,
    deleteRight,
    superuser,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbUser> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('pin')) {
      context.handle(
        _pinMeta,
        pin.isAcceptableOrUnknown(data['pin']!, _pinMeta),
      );
    }
    if (data.containsKey('change_quantity_right')) {
      context.handle(
        _changeQuantityRightMeta,
        changeQuantityRight.isAcceptableOrUnknown(
          data['change_quantity_right']!,
          _changeQuantityRightMeta,
        ),
      );
    }
    if (data.containsKey('all_tables_open_right')) {
      context.handle(
        _allTablesOpenRightMeta,
        allTablesOpenRight.isAcceptableOrUnknown(
          data['all_tables_open_right']!,
          _allTablesOpenRightMeta,
        ),
      );
    }
    if (data.containsKey('delete_right')) {
      context.handle(
        _deleteRightMeta,
        deleteRight.isAcceptableOrUnknown(
          data['delete_right']!,
          _deleteRightMeta,
        ),
      );
    }
    if (data.containsKey('superuser')) {
      context.handle(
        _superuserMeta,
        superuser.isAcceptableOrUnknown(data['superuser']!, _superuserMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  DbUser map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbUser(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      pin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pin'],
      )!,
      changeQuantityRight: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}change_quantity_right'],
      )!,
      allTablesOpenRight: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_tables_open_right'],
      )!,
      deleteRight: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}delete_right'],
      )!,
      superuser: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}superuser'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class DbUser extends DataClass implements Insertable<DbUser> {
  final String code;
  final String username;
  final int pin;
  final bool changeQuantityRight;
  final bool allTablesOpenRight;
  final bool deleteRight;
  final bool superuser;
  const DbUser({
    required this.code,
    required this.username,
    required this.pin,
    required this.changeQuantityRight,
    required this.allTablesOpenRight,
    required this.deleteRight,
    required this.superuser,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['username'] = Variable<String>(username);
    map['pin'] = Variable<int>(pin);
    map['change_quantity_right'] = Variable<bool>(changeQuantityRight);
    map['all_tables_open_right'] = Variable<bool>(allTablesOpenRight);
    map['delete_right'] = Variable<bool>(deleteRight);
    map['superuser'] = Variable<bool>(superuser);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      code: Value(code),
      username: Value(username),
      pin: Value(pin),
      changeQuantityRight: Value(changeQuantityRight),
      allTablesOpenRight: Value(allTablesOpenRight),
      deleteRight: Value(deleteRight),
      superuser: Value(superuser),
    );
  }

  factory DbUser.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbUser(
      code: serializer.fromJson<String>(json['code']),
      username: serializer.fromJson<String>(json['username']),
      pin: serializer.fromJson<int>(json['pin']),
      changeQuantityRight: serializer.fromJson<bool>(
        json['changeQuantityRight'],
      ),
      allTablesOpenRight: serializer.fromJson<bool>(json['allTablesOpenRight']),
      deleteRight: serializer.fromJson<bool>(json['deleteRight']),
      superuser: serializer.fromJson<bool>(json['superuser']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'username': serializer.toJson<String>(username),
      'pin': serializer.toJson<int>(pin),
      'changeQuantityRight': serializer.toJson<bool>(changeQuantityRight),
      'allTablesOpenRight': serializer.toJson<bool>(allTablesOpenRight),
      'deleteRight': serializer.toJson<bool>(deleteRight),
      'superuser': serializer.toJson<bool>(superuser),
    };
  }

  DbUser copyWith({
    String? code,
    String? username,
    int? pin,
    bool? changeQuantityRight,
    bool? allTablesOpenRight,
    bool? deleteRight,
    bool? superuser,
  }) => DbUser(
    code: code ?? this.code,
    username: username ?? this.username,
    pin: pin ?? this.pin,
    changeQuantityRight: changeQuantityRight ?? this.changeQuantityRight,
    allTablesOpenRight: allTablesOpenRight ?? this.allTablesOpenRight,
    deleteRight: deleteRight ?? this.deleteRight,
    superuser: superuser ?? this.superuser,
  );
  DbUser copyWithCompanion(UsersCompanion data) {
    return DbUser(
      code: data.code.present ? data.code.value : this.code,
      username: data.username.present ? data.username.value : this.username,
      pin: data.pin.present ? data.pin.value : this.pin,
      changeQuantityRight: data.changeQuantityRight.present
          ? data.changeQuantityRight.value
          : this.changeQuantityRight,
      allTablesOpenRight: data.allTablesOpenRight.present
          ? data.allTablesOpenRight.value
          : this.allTablesOpenRight,
      deleteRight: data.deleteRight.present
          ? data.deleteRight.value
          : this.deleteRight,
      superuser: data.superuser.present ? data.superuser.value : this.superuser,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbUser(')
          ..write('code: $code, ')
          ..write('username: $username, ')
          ..write('pin: $pin, ')
          ..write('changeQuantityRight: $changeQuantityRight, ')
          ..write('allTablesOpenRight: $allTablesOpenRight, ')
          ..write('deleteRight: $deleteRight, ')
          ..write('superuser: $superuser')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    code,
    username,
    pin,
    changeQuantityRight,
    allTablesOpenRight,
    deleteRight,
    superuser,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbUser &&
          other.code == this.code &&
          other.username == this.username &&
          other.pin == this.pin &&
          other.changeQuantityRight == this.changeQuantityRight &&
          other.allTablesOpenRight == this.allTablesOpenRight &&
          other.deleteRight == this.deleteRight &&
          other.superuser == this.superuser);
}

class UsersCompanion extends UpdateCompanion<DbUser> {
  final Value<String> code;
  final Value<String> username;
  final Value<int> pin;
  final Value<bool> changeQuantityRight;
  final Value<bool> allTablesOpenRight;
  final Value<bool> deleteRight;
  final Value<bool> superuser;
  final Value<int> rowid;
  const UsersCompanion({
    this.code = const Value.absent(),
    this.username = const Value.absent(),
    this.pin = const Value.absent(),
    this.changeQuantityRight = const Value.absent(),
    this.allTablesOpenRight = const Value.absent(),
    this.deleteRight = const Value.absent(),
    this.superuser = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String code,
    this.username = const Value.absent(),
    this.pin = const Value.absent(),
    this.changeQuantityRight = const Value.absent(),
    this.allTablesOpenRight = const Value.absent(),
    this.deleteRight = const Value.absent(),
    this.superuser = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : code = Value(code);
  static Insertable<DbUser> custom({
    Expression<String>? code,
    Expression<String>? username,
    Expression<int>? pin,
    Expression<bool>? changeQuantityRight,
    Expression<bool>? allTablesOpenRight,
    Expression<bool>? deleteRight,
    Expression<bool>? superuser,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (username != null) 'username': username,
      if (pin != null) 'pin': pin,
      if (changeQuantityRight != null)
        'change_quantity_right': changeQuantityRight,
      if (allTablesOpenRight != null)
        'all_tables_open_right': allTablesOpenRight,
      if (deleteRight != null) 'delete_right': deleteRight,
      if (superuser != null) 'superuser': superuser,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? code,
    Value<String>? username,
    Value<int>? pin,
    Value<bool>? changeQuantityRight,
    Value<bool>? allTablesOpenRight,
    Value<bool>? deleteRight,
    Value<bool>? superuser,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      code: code ?? this.code,
      username: username ?? this.username,
      pin: pin ?? this.pin,
      changeQuantityRight: changeQuantityRight ?? this.changeQuantityRight,
      allTablesOpenRight: allTablesOpenRight ?? this.allTablesOpenRight,
      deleteRight: deleteRight ?? this.deleteRight,
      superuser: superuser ?? this.superuser,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (pin.present) {
      map['pin'] = Variable<int>(pin.value);
    }
    if (changeQuantityRight.present) {
      map['change_quantity_right'] = Variable<bool>(changeQuantityRight.value);
    }
    if (allTablesOpenRight.present) {
      map['all_tables_open_right'] = Variable<bool>(allTablesOpenRight.value);
    }
    if (deleteRight.present) {
      map['delete_right'] = Variable<bool>(deleteRight.value);
    }
    if (superuser.present) {
      map['superuser'] = Variable<bool>(superuser.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('code: $code, ')
          ..write('username: $username, ')
          ..write('pin: $pin, ')
          ..write('changeQuantityRight: $changeQuantityRight, ')
          ..write('allTablesOpenRight: $allTablesOpenRight, ')
          ..write('deleteRight: $deleteRight, ')
          ..write('superuser: $superuser, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ArticlesTable extends Articles
    with TableInfo<$ArticlesTable, DbArticle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<int> code = GeneratedColumn<int>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _groupCodeMeta = const VerificationMeta(
    'groupCode',
  );
  @override
  late final GeneratedColumn<String> groupCode = GeneratedColumn<String>(
    'group_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _orderNoMeta = const VerificationMeta(
    'orderNo',
  );
  @override
  late final GeneratedColumn<int> orderNo = GeneratedColumn<int>(
    'order_num',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    code,
    name,
    price,
    unit,
    groupCode,
    orderNo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'articles';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbArticle> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('group_code')) {
      context.handle(
        _groupCodeMeta,
        groupCode.isAcceptableOrUnknown(data['group_code']!, _groupCodeMeta),
      );
    }
    if (data.containsKey('order_num')) {
      context.handle(
        _orderNoMeta,
        orderNo.isAcceptableOrUnknown(data['order_num']!, _orderNoMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  DbArticle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbArticle(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      groupCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_code'],
      )!,
      orderNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_num'],
      )!,
    );
  }

  @override
  $ArticlesTable createAlias(String alias) {
    return $ArticlesTable(attachedDatabase, alias);
  }
}

class DbArticle extends DataClass implements Insertable<DbArticle> {
  final int code;
  final String name;
  final double price;
  final String unit;
  final String groupCode;
  final int orderNo;
  const DbArticle({
    required this.code,
    required this.name,
    required this.price,
    required this.unit,
    required this.groupCode,
    required this.orderNo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<int>(code);
    map['name'] = Variable<String>(name);
    map['price'] = Variable<double>(price);
    map['unit'] = Variable<String>(unit);
    map['group_code'] = Variable<String>(groupCode);
    map['order_num'] = Variable<int>(orderNo);
    return map;
  }

  ArticlesCompanion toCompanion(bool nullToAbsent) {
    return ArticlesCompanion(
      code: Value(code),
      name: Value(name),
      price: Value(price),
      unit: Value(unit),
      groupCode: Value(groupCode),
      orderNo: Value(orderNo),
    );
  }

  factory DbArticle.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbArticle(
      code: serializer.fromJson<int>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      price: serializer.fromJson<double>(json['price']),
      unit: serializer.fromJson<String>(json['unit']),
      groupCode: serializer.fromJson<String>(json['groupCode']),
      orderNo: serializer.fromJson<int>(json['orderNo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<int>(code),
      'name': serializer.toJson<String>(name),
      'price': serializer.toJson<double>(price),
      'unit': serializer.toJson<String>(unit),
      'groupCode': serializer.toJson<String>(groupCode),
      'orderNo': serializer.toJson<int>(orderNo),
    };
  }

  DbArticle copyWith({
    int? code,
    String? name,
    double? price,
    String? unit,
    String? groupCode,
    int? orderNo,
  }) => DbArticle(
    code: code ?? this.code,
    name: name ?? this.name,
    price: price ?? this.price,
    unit: unit ?? this.unit,
    groupCode: groupCode ?? this.groupCode,
    orderNo: orderNo ?? this.orderNo,
  );
  DbArticle copyWithCompanion(ArticlesCompanion data) {
    return DbArticle(
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      price: data.price.present ? data.price.value : this.price,
      unit: data.unit.present ? data.unit.value : this.unit,
      groupCode: data.groupCode.present ? data.groupCode.value : this.groupCode,
      orderNo: data.orderNo.present ? data.orderNo.value : this.orderNo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbArticle(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('price: $price, ')
          ..write('unit: $unit, ')
          ..write('groupCode: $groupCode, ')
          ..write('orderNo: $orderNo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, name, price, unit, groupCode, orderNo);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbArticle &&
          other.code == this.code &&
          other.name == this.name &&
          other.price == this.price &&
          other.unit == this.unit &&
          other.groupCode == this.groupCode &&
          other.orderNo == this.orderNo);
}

class ArticlesCompanion extends UpdateCompanion<DbArticle> {
  final Value<int> code;
  final Value<String> name;
  final Value<double> price;
  final Value<String> unit;
  final Value<String> groupCode;
  final Value<int> orderNo;
  const ArticlesCompanion({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.price = const Value.absent(),
    this.unit = const Value.absent(),
    this.groupCode = const Value.absent(),
    this.orderNo = const Value.absent(),
  });
  ArticlesCompanion.insert({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.price = const Value.absent(),
    this.unit = const Value.absent(),
    this.groupCode = const Value.absent(),
    this.orderNo = const Value.absent(),
  });
  static Insertable<DbArticle> custom({
    Expression<int>? code,
    Expression<String>? name,
    Expression<double>? price,
    Expression<String>? unit,
    Expression<String>? groupCode,
    Expression<int>? orderNo,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (price != null) 'price': price,
      if (unit != null) 'unit': unit,
      if (groupCode != null) 'group_code': groupCode,
      if (orderNo != null) 'order_num': orderNo,
    });
  }

  ArticlesCompanion copyWith({
    Value<int>? code,
    Value<String>? name,
    Value<double>? price,
    Value<String>? unit,
    Value<String>? groupCode,
    Value<int>? orderNo,
  }) {
    return ArticlesCompanion(
      code: code ?? this.code,
      name: name ?? this.name,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      groupCode: groupCode ?? this.groupCode,
      orderNo: orderNo ?? this.orderNo,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<int>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (groupCode.present) {
      map['group_code'] = Variable<String>(groupCode.value);
    }
    if (orderNo.present) {
      map['order_num'] = Variable<int>(orderNo.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticlesCompanion(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('price: $price, ')
          ..write('unit: $unit, ')
          ..write('groupCode: $groupCode, ')
          ..write('orderNo: $orderNo')
          ..write(')'))
        .toString();
  }
}

class $ArticleGroupsTable extends ArticleGroups
    with TableInfo<$ArticleGroupsTable, DbArticleGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticleGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _orderNoMeta = const VerificationMeta(
    'orderNo',
  );
  @override
  late final GeneratedColumn<int> orderNo = GeneratedColumn<int>(
    'order_num',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [code, name, orderNo];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'article_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbArticleGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('order_num')) {
      context.handle(
        _orderNoMeta,
        orderNo.isAcceptableOrUnknown(data['order_num']!, _orderNoMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  DbArticleGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbArticleGroup(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      orderNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_num'],
      )!,
    );
  }

  @override
  $ArticleGroupsTable createAlias(String alias) {
    return $ArticleGroupsTable(attachedDatabase, alias);
  }
}

class DbArticleGroup extends DataClass implements Insertable<DbArticleGroup> {
  final String code;
  final String name;
  final int orderNo;
  const DbArticleGroup({
    required this.code,
    required this.name,
    required this.orderNo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['order_num'] = Variable<int>(orderNo);
    return map;
  }

  ArticleGroupsCompanion toCompanion(bool nullToAbsent) {
    return ArticleGroupsCompanion(
      code: Value(code),
      name: Value(name),
      orderNo: Value(orderNo),
    );
  }

  factory DbArticleGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbArticleGroup(
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      orderNo: serializer.fromJson<int>(json['orderNo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'orderNo': serializer.toJson<int>(orderNo),
    };
  }

  DbArticleGroup copyWith({String? code, String? name, int? orderNo}) =>
      DbArticleGroup(
        code: code ?? this.code,
        name: name ?? this.name,
        orderNo: orderNo ?? this.orderNo,
      );
  DbArticleGroup copyWithCompanion(ArticleGroupsCompanion data) {
    return DbArticleGroup(
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      orderNo: data.orderNo.present ? data.orderNo.value : this.orderNo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbArticleGroup(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('orderNo: $orderNo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, name, orderNo);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbArticleGroup &&
          other.code == this.code &&
          other.name == this.name &&
          other.orderNo == this.orderNo);
}

class ArticleGroupsCompanion extends UpdateCompanion<DbArticleGroup> {
  final Value<String> code;
  final Value<String> name;
  final Value<int> orderNo;
  final Value<int> rowid;
  const ArticleGroupsCompanion({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.orderNo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArticleGroupsCompanion.insert({
    required String code,
    this.name = const Value.absent(),
    this.orderNo = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : code = Value(code);
  static Insertable<DbArticleGroup> custom({
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? orderNo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (orderNo != null) 'order_num': orderNo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArticleGroupsCompanion copyWith({
    Value<String>? code,
    Value<String>? name,
    Value<int>? orderNo,
    Value<int>? rowid,
  }) {
    return ArticleGroupsCompanion(
      code: code ?? this.code,
      name: name ?? this.name,
      orderNo: orderNo ?? this.orderNo,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (orderNo.present) {
      map['order_num'] = Variable<int>(orderNo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticleGroupsCompanion(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('orderNo: $orderNo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VenueTablesTable extends VenueTables
    with TableInfo<$VenueTablesTable, DbVenueTable> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VenueTablesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<int> code = GeneratedColumn<int>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _userCodeMeta = const VerificationMeta(
    'userCode',
  );
  @override
  late final GeneratedColumn<String> userCode = GeneratedColumn<String>(
    'user_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _itemCountMeta = const VerificationMeta(
    'itemCount',
  );
  @override
  late final GeneratedColumn<int> itemCount = GeneratedColumn<int>(
    'item_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [code, name, userCode, itemCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'venue_tables';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbVenueTable> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('user_code')) {
      context.handle(
        _userCodeMeta,
        userCode.isAcceptableOrUnknown(data['user_code']!, _userCodeMeta),
      );
    }
    if (data.containsKey('item_count')) {
      context.handle(
        _itemCountMeta,
        itemCount.isAcceptableOrUnknown(data['item_count']!, _itemCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  DbVenueTable map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbVenueTable(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      userCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_code'],
      )!,
      itemCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_count'],
      )!,
    );
  }

  @override
  $VenueTablesTable createAlias(String alias) {
    return $VenueTablesTable(attachedDatabase, alias);
  }
}

class DbVenueTable extends DataClass implements Insertable<DbVenueTable> {
  final int code;
  final String name;
  final String userCode;
  final int itemCount;
  const DbVenueTable({
    required this.code,
    required this.name,
    required this.userCode,
    required this.itemCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<int>(code);
    map['name'] = Variable<String>(name);
    map['user_code'] = Variable<String>(userCode);
    map['item_count'] = Variable<int>(itemCount);
    return map;
  }

  VenueTablesCompanion toCompanion(bool nullToAbsent) {
    return VenueTablesCompanion(
      code: Value(code),
      name: Value(name),
      userCode: Value(userCode),
      itemCount: Value(itemCount),
    );
  }

  factory DbVenueTable.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbVenueTable(
      code: serializer.fromJson<int>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      userCode: serializer.fromJson<String>(json['userCode']),
      itemCount: serializer.fromJson<int>(json['itemCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<int>(code),
      'name': serializer.toJson<String>(name),
      'userCode': serializer.toJson<String>(userCode),
      'itemCount': serializer.toJson<int>(itemCount),
    };
  }

  DbVenueTable copyWith({
    int? code,
    String? name,
    String? userCode,
    int? itemCount,
  }) => DbVenueTable(
    code: code ?? this.code,
    name: name ?? this.name,
    userCode: userCode ?? this.userCode,
    itemCount: itemCount ?? this.itemCount,
  );
  DbVenueTable copyWithCompanion(VenueTablesCompanion data) {
    return DbVenueTable(
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      userCode: data.userCode.present ? data.userCode.value : this.userCode,
      itemCount: data.itemCount.present ? data.itemCount.value : this.itemCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbVenueTable(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('userCode: $userCode, ')
          ..write('itemCount: $itemCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, name, userCode, itemCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbVenueTable &&
          other.code == this.code &&
          other.name == this.name &&
          other.userCode == this.userCode &&
          other.itemCount == this.itemCount);
}

class VenueTablesCompanion extends UpdateCompanion<DbVenueTable> {
  final Value<int> code;
  final Value<String> name;
  final Value<String> userCode;
  final Value<int> itemCount;
  const VenueTablesCompanion({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.userCode = const Value.absent(),
    this.itemCount = const Value.absent(),
  });
  VenueTablesCompanion.insert({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.userCode = const Value.absent(),
    this.itemCount = const Value.absent(),
  });
  static Insertable<DbVenueTable> custom({
    Expression<int>? code,
    Expression<String>? name,
    Expression<String>? userCode,
    Expression<int>? itemCount,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (userCode != null) 'user_code': userCode,
      if (itemCount != null) 'item_count': itemCount,
    });
  }

  VenueTablesCompanion copyWith({
    Value<int>? code,
    Value<String>? name,
    Value<String>? userCode,
    Value<int>? itemCount,
  }) {
    return VenueTablesCompanion(
      code: code ?? this.code,
      name: name ?? this.name,
      userCode: userCode ?? this.userCode,
      itemCount: itemCount ?? this.itemCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<int>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (userCode.present) {
      map['user_code'] = Variable<String>(userCode.value);
    }
    if (itemCount.present) {
      map['item_count'] = Variable<int>(itemCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VenueTablesCompanion(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('userCode: $userCode, ')
          ..write('itemCount: $itemCount')
          ..write(')'))
        .toString();
  }
}

class $TerracesTable extends Terraces
    with TableInfo<$TerracesTable, DbTerrace> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TerracesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tableFromMeta = const VerificationMeta(
    'tableFrom',
  );
  @override
  late final GeneratedColumn<int> tableFrom = GeneratedColumn<int>(
    'table_from',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tableToMeta = const VerificationMeta(
    'tableTo',
  );
  @override
  late final GeneratedColumn<int> tableTo = GeneratedColumn<int>(
    'table_to',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [code, tableFrom, tableTo];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'terraces';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbTerrace> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('table_from')) {
      context.handle(
        _tableFromMeta,
        tableFrom.isAcceptableOrUnknown(data['table_from']!, _tableFromMeta),
      );
    }
    if (data.containsKey('table_to')) {
      context.handle(
        _tableToMeta,
        tableTo.isAcceptableOrUnknown(data['table_to']!, _tableToMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  DbTerrace map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbTerrace(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      tableFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}table_from'],
      )!,
      tableTo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}table_to'],
      )!,
    );
  }

  @override
  $TerracesTable createAlias(String alias) {
    return $TerracesTable(attachedDatabase, alias);
  }
}

class DbTerrace extends DataClass implements Insertable<DbTerrace> {
  final String code;
  final int tableFrom;
  final int tableTo;
  const DbTerrace({
    required this.code,
    required this.tableFrom,
    required this.tableTo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['table_from'] = Variable<int>(tableFrom);
    map['table_to'] = Variable<int>(tableTo);
    return map;
  }

  TerracesCompanion toCompanion(bool nullToAbsent) {
    return TerracesCompanion(
      code: Value(code),
      tableFrom: Value(tableFrom),
      tableTo: Value(tableTo),
    );
  }

  factory DbTerrace.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbTerrace(
      code: serializer.fromJson<String>(json['code']),
      tableFrom: serializer.fromJson<int>(json['tableFrom']),
      tableTo: serializer.fromJson<int>(json['tableTo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'tableFrom': serializer.toJson<int>(tableFrom),
      'tableTo': serializer.toJson<int>(tableTo),
    };
  }

  DbTerrace copyWith({String? code, int? tableFrom, int? tableTo}) => DbTerrace(
    code: code ?? this.code,
    tableFrom: tableFrom ?? this.tableFrom,
    tableTo: tableTo ?? this.tableTo,
  );
  DbTerrace copyWithCompanion(TerracesCompanion data) {
    return DbTerrace(
      code: data.code.present ? data.code.value : this.code,
      tableFrom: data.tableFrom.present ? data.tableFrom.value : this.tableFrom,
      tableTo: data.tableTo.present ? data.tableTo.value : this.tableTo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbTerrace(')
          ..write('code: $code, ')
          ..write('tableFrom: $tableFrom, ')
          ..write('tableTo: $tableTo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, tableFrom, tableTo);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbTerrace &&
          other.code == this.code &&
          other.tableFrom == this.tableFrom &&
          other.tableTo == this.tableTo);
}

class TerracesCompanion extends UpdateCompanion<DbTerrace> {
  final Value<String> code;
  final Value<int> tableFrom;
  final Value<int> tableTo;
  final Value<int> rowid;
  const TerracesCompanion({
    this.code = const Value.absent(),
    this.tableFrom = const Value.absent(),
    this.tableTo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TerracesCompanion.insert({
    required String code,
    this.tableFrom = const Value.absent(),
    this.tableTo = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : code = Value(code);
  static Insertable<DbTerrace> custom({
    Expression<String>? code,
    Expression<int>? tableFrom,
    Expression<int>? tableTo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (tableFrom != null) 'table_from': tableFrom,
      if (tableTo != null) 'table_to': tableTo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TerracesCompanion copyWith({
    Value<String>? code,
    Value<int>? tableFrom,
    Value<int>? tableTo,
    Value<int>? rowid,
  }) {
    return TerracesCompanion(
      code: code ?? this.code,
      tableFrom: tableFrom ?? this.tableFrom,
      tableTo: tableTo ?? this.tableTo,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (tableFrom.present) {
      map['table_from'] = Variable<int>(tableFrom.value);
    }
    if (tableTo.present) {
      map['table_to'] = Variable<int>(tableTo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TerracesCompanion(')
          ..write('code: $code, ')
          ..write('tableFrom: $tableFrom, ')
          ..write('tableTo: $tableTo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemarksTable extends Remarks with TableInfo<$RemarksTable, DbRemark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<int> itemId = GeneratedColumn<int>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, itemId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbRemark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbRemark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbRemark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_id'],
      )!,
    );
  }

  @override
  $RemarksTable createAlias(String alias) {
    return $RemarksTable(attachedDatabase, alias);
  }
}

class DbRemark extends DataClass implements Insertable<DbRemark> {
  final int id;
  final String name;
  final int itemId;
  const DbRemark({required this.id, required this.name, required this.itemId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['item_id'] = Variable<int>(itemId);
    return map;
  }

  RemarksCompanion toCompanion(bool nullToAbsent) {
    return RemarksCompanion(
      id: Value(id),
      name: Value(name),
      itemId: Value(itemId),
    );
  }

  factory DbRemark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbRemark(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      itemId: serializer.fromJson<int>(json['itemId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'itemId': serializer.toJson<int>(itemId),
    };
  }

  DbRemark copyWith({int? id, String? name, int? itemId}) => DbRemark(
    id: id ?? this.id,
    name: name ?? this.name,
    itemId: itemId ?? this.itemId,
  );
  DbRemark copyWithCompanion(RemarksCompanion data) {
    return DbRemark(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbRemark(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('itemId: $itemId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, itemId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbRemark &&
          other.id == this.id &&
          other.name == this.name &&
          other.itemId == this.itemId);
}

class RemarksCompanion extends UpdateCompanion<DbRemark> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> itemId;
  const RemarksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.itemId = const Value.absent(),
  });
  RemarksCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.itemId = const Value.absent(),
  });
  static Insertable<DbRemark> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? itemId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (itemId != null) 'item_id': itemId,
    });
  }

  RemarksCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? itemId,
  }) {
    return RemarksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      itemId: itemId ?? this.itemId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<int>(itemId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemarksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('itemId: $itemId')
          ..write(')'))
        .toString();
  }
}

class $OrdersTable extends Orders with TableInfo<$OrdersTable, DbOrder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
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
  static const VerificationMeta _orderTimeMeta = const VerificationMeta(
    'orderTime',
  );
  @override
  late final GeneratedColumn<int> orderTime = GeneratedColumn<int>(
    'order_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _userCodeMeta = const VerificationMeta(
    'userCode',
  );
  @override
  late final GeneratedColumn<String> userCode = GeneratedColumn<String>(
    'user_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tableCodeMeta = const VerificationMeta(
    'tableCode',
  );
  @override
  late final GeneratedColumn<int> tableCode = GeneratedColumn<int>(
    'table_code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<OrderItem>, String> items =
      GeneratedColumn<String>(
        'items',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<OrderItem>>($OrdersTable.$converteritems);
  static const VerificationMeta _pendingMeta = const VerificationMeta(
    'pending',
  );
  @override
  late final GeneratedColumn<bool> pending = GeneratedColumn<bool>(
    'pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sentMeta = const VerificationMeta('sent');
  @override
  late final GeneratedColumn<bool> sent = GeneratedColumn<bool>(
    'sent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orderTime,
    userCode,
    tableCode,
    items,
    pending,
    sent,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'orders';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbOrder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('order_time')) {
      context.handle(
        _orderTimeMeta,
        orderTime.isAcceptableOrUnknown(data['order_time']!, _orderTimeMeta),
      );
    }
    if (data.containsKey('user_code')) {
      context.handle(
        _userCodeMeta,
        userCode.isAcceptableOrUnknown(data['user_code']!, _userCodeMeta),
      );
    }
    if (data.containsKey('table_code')) {
      context.handle(
        _tableCodeMeta,
        tableCode.isAcceptableOrUnknown(data['table_code']!, _tableCodeMeta),
      );
    }
    if (data.containsKey('pending')) {
      context.handle(
        _pendingMeta,
        pending.isAcceptableOrUnknown(data['pending']!, _pendingMeta),
      );
    }
    if (data.containsKey('sent')) {
      context.handle(
        _sentMeta,
        sent.isAcceptableOrUnknown(data['sent']!, _sentMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbOrder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbOrder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      orderTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_time'],
      )!,
      userCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_code'],
      )!,
      tableCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}table_code'],
      )!,
      items: $OrdersTable.$converteritems.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}items'],
        )!,
      ),
      pending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending'],
      )!,
      sent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sent'],
      )!,
    );
  }

  @override
  $OrdersTable createAlias(String alias) {
    return $OrdersTable(attachedDatabase, alias);
  }

  static TypeConverter<List<OrderItem>, String> $converteritems =
      const OrderItemListConverter();
}

class DbOrder extends DataClass implements Insertable<DbOrder> {
  final int id;
  final int orderTime;
  final String userCode;
  final int tableCode;
  final List<OrderItem> items;
  final bool pending;
  final bool sent;
  const DbOrder({
    required this.id,
    required this.orderTime,
    required this.userCode,
    required this.tableCode,
    required this.items,
    required this.pending,
    required this.sent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['order_time'] = Variable<int>(orderTime);
    map['user_code'] = Variable<String>(userCode);
    map['table_code'] = Variable<int>(tableCode);
    {
      map['items'] = Variable<String>(
        $OrdersTable.$converteritems.toSql(items),
      );
    }
    map['pending'] = Variable<bool>(pending);
    map['sent'] = Variable<bool>(sent);
    return map;
  }

  OrdersCompanion toCompanion(bool nullToAbsent) {
    return OrdersCompanion(
      id: Value(id),
      orderTime: Value(orderTime),
      userCode: Value(userCode),
      tableCode: Value(tableCode),
      items: Value(items),
      pending: Value(pending),
      sent: Value(sent),
    );
  }

  factory DbOrder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbOrder(
      id: serializer.fromJson<int>(json['id']),
      orderTime: serializer.fromJson<int>(json['orderTime']),
      userCode: serializer.fromJson<String>(json['userCode']),
      tableCode: serializer.fromJson<int>(json['tableCode']),
      items: serializer.fromJson<List<OrderItem>>(json['items']),
      pending: serializer.fromJson<bool>(json['pending']),
      sent: serializer.fromJson<bool>(json['sent']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'orderTime': serializer.toJson<int>(orderTime),
      'userCode': serializer.toJson<String>(userCode),
      'tableCode': serializer.toJson<int>(tableCode),
      'items': serializer.toJson<List<OrderItem>>(items),
      'pending': serializer.toJson<bool>(pending),
      'sent': serializer.toJson<bool>(sent),
    };
  }

  DbOrder copyWith({
    int? id,
    int? orderTime,
    String? userCode,
    int? tableCode,
    List<OrderItem>? items,
    bool? pending,
    bool? sent,
  }) => DbOrder(
    id: id ?? this.id,
    orderTime: orderTime ?? this.orderTime,
    userCode: userCode ?? this.userCode,
    tableCode: tableCode ?? this.tableCode,
    items: items ?? this.items,
    pending: pending ?? this.pending,
    sent: sent ?? this.sent,
  );
  DbOrder copyWithCompanion(OrdersCompanion data) {
    return DbOrder(
      id: data.id.present ? data.id.value : this.id,
      orderTime: data.orderTime.present ? data.orderTime.value : this.orderTime,
      userCode: data.userCode.present ? data.userCode.value : this.userCode,
      tableCode: data.tableCode.present ? data.tableCode.value : this.tableCode,
      items: data.items.present ? data.items.value : this.items,
      pending: data.pending.present ? data.pending.value : this.pending,
      sent: data.sent.present ? data.sent.value : this.sent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbOrder(')
          ..write('id: $id, ')
          ..write('orderTime: $orderTime, ')
          ..write('userCode: $userCode, ')
          ..write('tableCode: $tableCode, ')
          ..write('items: $items, ')
          ..write('pending: $pending, ')
          ..write('sent: $sent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, orderTime, userCode, tableCode, items, pending, sent);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbOrder &&
          other.id == this.id &&
          other.orderTime == this.orderTime &&
          other.userCode == this.userCode &&
          other.tableCode == this.tableCode &&
          other.items == this.items &&
          other.pending == this.pending &&
          other.sent == this.sent);
}

class OrdersCompanion extends UpdateCompanion<DbOrder> {
  final Value<int> id;
  final Value<int> orderTime;
  final Value<String> userCode;
  final Value<int> tableCode;
  final Value<List<OrderItem>> items;
  final Value<bool> pending;
  final Value<bool> sent;
  const OrdersCompanion({
    this.id = const Value.absent(),
    this.orderTime = const Value.absent(),
    this.userCode = const Value.absent(),
    this.tableCode = const Value.absent(),
    this.items = const Value.absent(),
    this.pending = const Value.absent(),
    this.sent = const Value.absent(),
  });
  OrdersCompanion.insert({
    this.id = const Value.absent(),
    this.orderTime = const Value.absent(),
    this.userCode = const Value.absent(),
    this.tableCode = const Value.absent(),
    this.items = const Value.absent(),
    this.pending = const Value.absent(),
    this.sent = const Value.absent(),
  });
  static Insertable<DbOrder> custom({
    Expression<int>? id,
    Expression<int>? orderTime,
    Expression<String>? userCode,
    Expression<int>? tableCode,
    Expression<String>? items,
    Expression<bool>? pending,
    Expression<bool>? sent,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orderTime != null) 'order_time': orderTime,
      if (userCode != null) 'user_code': userCode,
      if (tableCode != null) 'table_code': tableCode,
      if (items != null) 'items': items,
      if (pending != null) 'pending': pending,
      if (sent != null) 'sent': sent,
    });
  }

  OrdersCompanion copyWith({
    Value<int>? id,
    Value<int>? orderTime,
    Value<String>? userCode,
    Value<int>? tableCode,
    Value<List<OrderItem>>? items,
    Value<bool>? pending,
    Value<bool>? sent,
  }) {
    return OrdersCompanion(
      id: id ?? this.id,
      orderTime: orderTime ?? this.orderTime,
      userCode: userCode ?? this.userCode,
      tableCode: tableCode ?? this.tableCode,
      items: items ?? this.items,
      pending: pending ?? this.pending,
      sent: sent ?? this.sent,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (orderTime.present) {
      map['order_time'] = Variable<int>(orderTime.value);
    }
    if (userCode.present) {
      map['user_code'] = Variable<String>(userCode.value);
    }
    if (tableCode.present) {
      map['table_code'] = Variable<int>(tableCode.value);
    }
    if (items.present) {
      map['items'] = Variable<String>(
        $OrdersTable.$converteritems.toSql(items.value),
      );
    }
    if (pending.present) {
      map['pending'] = Variable<bool>(pending.value);
    }
    if (sent.present) {
      map['sent'] = Variable<bool>(sent.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrdersCompanion(')
          ..write('id: $id, ')
          ..write('orderTime: $orderTime, ')
          ..write('userCode: $userCode, ')
          ..write('tableCode: $tableCode, ')
          ..write('items: $items, ')
          ..write('pending: $pending, ')
          ..write('sent: $sent')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ArticlesTable articles = $ArticlesTable(this);
  late final $ArticleGroupsTable articleGroups = $ArticleGroupsTable(this);
  late final $VenueTablesTable venueTables = $VenueTablesTable(this);
  late final $TerracesTable terraces = $TerracesTable(this);
  late final $RemarksTable remarks = $RemarksTable(this);
  late final $OrdersTable orders = $OrdersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    users,
    articles,
    articleGroups,
    venueTables,
    terraces,
    remarks,
    orders,
  ];
}

typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      required String code,
      Value<String> username,
      Value<int> pin,
      Value<bool> changeQuantityRight,
      Value<bool> allTablesOpenRight,
      Value<bool> deleteRight,
      Value<bool> superuser,
      Value<int> rowid,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<String> code,
      Value<String> username,
      Value<int> pin,
      Value<bool> changeQuantityRight,
      Value<bool> allTablesOpenRight,
      Value<bool> deleteRight,
      Value<bool> superuser,
      Value<int> rowid,
    });

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get changeQuantityRight => $composableBuilder(
    column: $table.changeQuantityRight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allTablesOpenRight => $composableBuilder(
    column: $table.allTablesOpenRight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleteRight => $composableBuilder(
    column: $table.deleteRight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get superuser => $composableBuilder(
    column: $table.superuser,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get changeQuantityRight => $composableBuilder(
    column: $table.changeQuantityRight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allTablesOpenRight => $composableBuilder(
    column: $table.allTablesOpenRight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleteRight => $composableBuilder(
    column: $table.deleteRight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get superuser => $composableBuilder(
    column: $table.superuser,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<int> get pin =>
      $composableBuilder(column: $table.pin, builder: (column) => column);

  GeneratedColumn<bool> get changeQuantityRight => $composableBuilder(
    column: $table.changeQuantityRight,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allTablesOpenRight => $composableBuilder(
    column: $table.allTablesOpenRight,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleteRight => $composableBuilder(
    column: $table.deleteRight,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get superuser =>
      $composableBuilder(column: $table.superuser, builder: (column) => column);
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          DbUser,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (DbUser, BaseReferences<_$AppDatabase, $UsersTable, DbUser>),
          DbUser,
          PrefetchHooks Function()
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
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
                Value<String> code = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<int> pin = const Value.absent(),
                Value<bool> changeQuantityRight = const Value.absent(),
                Value<bool> allTablesOpenRight = const Value.absent(),
                Value<bool> deleteRight = const Value.absent(),
                Value<bool> superuser = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                code: code,
                username: username,
                pin: pin,
                changeQuantityRight: changeQuantityRight,
                allTablesOpenRight: allTablesOpenRight,
                deleteRight: deleteRight,
                superuser: superuser,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                Value<String> username = const Value.absent(),
                Value<int> pin = const Value.absent(),
                Value<bool> changeQuantityRight = const Value.absent(),
                Value<bool> allTablesOpenRight = const Value.absent(),
                Value<bool> deleteRight = const Value.absent(),
                Value<bool> superuser = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                code: code,
                username: username,
                pin: pin,
                changeQuantityRight: changeQuantityRight,
                allTablesOpenRight: allTablesOpenRight,
                deleteRight: deleteRight,
                superuser: superuser,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      DbUser,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (DbUser, BaseReferences<_$AppDatabase, $UsersTable, DbUser>),
      DbUser,
      PrefetchHooks Function()
    >;
typedef $$ArticlesTableCreateCompanionBuilder =
    ArticlesCompanion Function({
      Value<int> code,
      Value<String> name,
      Value<double> price,
      Value<String> unit,
      Value<String> groupCode,
      Value<int> orderNo,
    });
typedef $$ArticlesTableUpdateCompanionBuilder =
    ArticlesCompanion Function({
      Value<int> code,
      Value<String> name,
      Value<double> price,
      Value<String> unit,
      Value<String> groupCode,
      Value<int> orderNo,
    });

class $$ArticlesTableFilterComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupCode => $composableBuilder(
    column: $table.groupCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderNo => $composableBuilder(
    column: $table.orderNo,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArticlesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupCode => $composableBuilder(
    column: $table.groupCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderNo => $composableBuilder(
    column: $table.orderNo,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArticlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get groupCode =>
      $composableBuilder(column: $table.groupCode, builder: (column) => column);

  GeneratedColumn<int> get orderNo =>
      $composableBuilder(column: $table.orderNo, builder: (column) => column);
}

class $$ArticlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArticlesTable,
          DbArticle,
          $$ArticlesTableFilterComposer,
          $$ArticlesTableOrderingComposer,
          $$ArticlesTableAnnotationComposer,
          $$ArticlesTableCreateCompanionBuilder,
          $$ArticlesTableUpdateCompanionBuilder,
          (DbArticle, BaseReferences<_$AppDatabase, $ArticlesTable, DbArticle>),
          DbArticle,
          PrefetchHooks Function()
        > {
  $$ArticlesTableTableManager(_$AppDatabase db, $ArticlesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String> groupCode = const Value.absent(),
                Value<int> orderNo = const Value.absent(),
              }) => ArticlesCompanion(
                code: code,
                name: name,
                price: price,
                unit: unit,
                groupCode: groupCode,
                orderNo: orderNo,
              ),
          createCompanionCallback:
              ({
                Value<int> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String> groupCode = const Value.absent(),
                Value<int> orderNo = const Value.absent(),
              }) => ArticlesCompanion.insert(
                code: code,
                name: name,
                price: price,
                unit: unit,
                groupCode: groupCode,
                orderNo: orderNo,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArticlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArticlesTable,
      DbArticle,
      $$ArticlesTableFilterComposer,
      $$ArticlesTableOrderingComposer,
      $$ArticlesTableAnnotationComposer,
      $$ArticlesTableCreateCompanionBuilder,
      $$ArticlesTableUpdateCompanionBuilder,
      (DbArticle, BaseReferences<_$AppDatabase, $ArticlesTable, DbArticle>),
      DbArticle,
      PrefetchHooks Function()
    >;
typedef $$ArticleGroupsTableCreateCompanionBuilder =
    ArticleGroupsCompanion Function({
      required String code,
      Value<String> name,
      Value<int> orderNo,
      Value<int> rowid,
    });
typedef $$ArticleGroupsTableUpdateCompanionBuilder =
    ArticleGroupsCompanion Function({
      Value<String> code,
      Value<String> name,
      Value<int> orderNo,
      Value<int> rowid,
    });

class $$ArticleGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $ArticleGroupsTable> {
  $$ArticleGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderNo => $composableBuilder(
    column: $table.orderNo,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArticleGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticleGroupsTable> {
  $$ArticleGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderNo => $composableBuilder(
    column: $table.orderNo,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArticleGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticleGroupsTable> {
  $$ArticleGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get orderNo =>
      $composableBuilder(column: $table.orderNo, builder: (column) => column);
}

class $$ArticleGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArticleGroupsTable,
          DbArticleGroup,
          $$ArticleGroupsTableFilterComposer,
          $$ArticleGroupsTableOrderingComposer,
          $$ArticleGroupsTableAnnotationComposer,
          $$ArticleGroupsTableCreateCompanionBuilder,
          $$ArticleGroupsTableUpdateCompanionBuilder,
          (
            DbArticleGroup,
            BaseReferences<_$AppDatabase, $ArticleGroupsTable, DbArticleGroup>,
          ),
          DbArticleGroup,
          PrefetchHooks Function()
        > {
  $$ArticleGroupsTableTableManager(_$AppDatabase db, $ArticleGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticleGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticleGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticleGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> orderNo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArticleGroupsCompanion(
                code: code,
                name: name,
                orderNo: orderNo,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                Value<String> name = const Value.absent(),
                Value<int> orderNo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArticleGroupsCompanion.insert(
                code: code,
                name: name,
                orderNo: orderNo,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArticleGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArticleGroupsTable,
      DbArticleGroup,
      $$ArticleGroupsTableFilterComposer,
      $$ArticleGroupsTableOrderingComposer,
      $$ArticleGroupsTableAnnotationComposer,
      $$ArticleGroupsTableCreateCompanionBuilder,
      $$ArticleGroupsTableUpdateCompanionBuilder,
      (
        DbArticleGroup,
        BaseReferences<_$AppDatabase, $ArticleGroupsTable, DbArticleGroup>,
      ),
      DbArticleGroup,
      PrefetchHooks Function()
    >;
typedef $$VenueTablesTableCreateCompanionBuilder =
    VenueTablesCompanion Function({
      Value<int> code,
      Value<String> name,
      Value<String> userCode,
      Value<int> itemCount,
    });
typedef $$VenueTablesTableUpdateCompanionBuilder =
    VenueTablesCompanion Function({
      Value<int> code,
      Value<String> name,
      Value<String> userCode,
      Value<int> itemCount,
    });

class $$VenueTablesTableFilterComposer
    extends Composer<_$AppDatabase, $VenueTablesTable> {
  $$VenueTablesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userCode => $composableBuilder(
    column: $table.userCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get itemCount => $composableBuilder(
    column: $table.itemCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VenueTablesTableOrderingComposer
    extends Composer<_$AppDatabase, $VenueTablesTable> {
  $$VenueTablesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userCode => $composableBuilder(
    column: $table.userCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get itemCount => $composableBuilder(
    column: $table.itemCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VenueTablesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VenueTablesTable> {
  $$VenueTablesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get userCode =>
      $composableBuilder(column: $table.userCode, builder: (column) => column);

  GeneratedColumn<int> get itemCount =>
      $composableBuilder(column: $table.itemCount, builder: (column) => column);
}

class $$VenueTablesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VenueTablesTable,
          DbVenueTable,
          $$VenueTablesTableFilterComposer,
          $$VenueTablesTableOrderingComposer,
          $$VenueTablesTableAnnotationComposer,
          $$VenueTablesTableCreateCompanionBuilder,
          $$VenueTablesTableUpdateCompanionBuilder,
          (
            DbVenueTable,
            BaseReferences<_$AppDatabase, $VenueTablesTable, DbVenueTable>,
          ),
          DbVenueTable,
          PrefetchHooks Function()
        > {
  $$VenueTablesTableTableManager(_$AppDatabase db, $VenueTablesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VenueTablesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VenueTablesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VenueTablesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> userCode = const Value.absent(),
                Value<int> itemCount = const Value.absent(),
              }) => VenueTablesCompanion(
                code: code,
                name: name,
                userCode: userCode,
                itemCount: itemCount,
              ),
          createCompanionCallback:
              ({
                Value<int> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> userCode = const Value.absent(),
                Value<int> itemCount = const Value.absent(),
              }) => VenueTablesCompanion.insert(
                code: code,
                name: name,
                userCode: userCode,
                itemCount: itemCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VenueTablesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VenueTablesTable,
      DbVenueTable,
      $$VenueTablesTableFilterComposer,
      $$VenueTablesTableOrderingComposer,
      $$VenueTablesTableAnnotationComposer,
      $$VenueTablesTableCreateCompanionBuilder,
      $$VenueTablesTableUpdateCompanionBuilder,
      (
        DbVenueTable,
        BaseReferences<_$AppDatabase, $VenueTablesTable, DbVenueTable>,
      ),
      DbVenueTable,
      PrefetchHooks Function()
    >;
typedef $$TerracesTableCreateCompanionBuilder =
    TerracesCompanion Function({
      required String code,
      Value<int> tableFrom,
      Value<int> tableTo,
      Value<int> rowid,
    });
typedef $$TerracesTableUpdateCompanionBuilder =
    TerracesCompanion Function({
      Value<String> code,
      Value<int> tableFrom,
      Value<int> tableTo,
      Value<int> rowid,
    });

class $$TerracesTableFilterComposer
    extends Composer<_$AppDatabase, $TerracesTable> {
  $$TerracesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tableFrom => $composableBuilder(
    column: $table.tableFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tableTo => $composableBuilder(
    column: $table.tableTo,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TerracesTableOrderingComposer
    extends Composer<_$AppDatabase, $TerracesTable> {
  $$TerracesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tableFrom => $composableBuilder(
    column: $table.tableFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tableTo => $composableBuilder(
    column: $table.tableTo,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TerracesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TerracesTable> {
  $$TerracesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<int> get tableFrom =>
      $composableBuilder(column: $table.tableFrom, builder: (column) => column);

  GeneratedColumn<int> get tableTo =>
      $composableBuilder(column: $table.tableTo, builder: (column) => column);
}

class $$TerracesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TerracesTable,
          DbTerrace,
          $$TerracesTableFilterComposer,
          $$TerracesTableOrderingComposer,
          $$TerracesTableAnnotationComposer,
          $$TerracesTableCreateCompanionBuilder,
          $$TerracesTableUpdateCompanionBuilder,
          (DbTerrace, BaseReferences<_$AppDatabase, $TerracesTable, DbTerrace>),
          DbTerrace,
          PrefetchHooks Function()
        > {
  $$TerracesTableTableManager(_$AppDatabase db, $TerracesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TerracesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TerracesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TerracesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> code = const Value.absent(),
                Value<int> tableFrom = const Value.absent(),
                Value<int> tableTo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TerracesCompanion(
                code: code,
                tableFrom: tableFrom,
                tableTo: tableTo,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                Value<int> tableFrom = const Value.absent(),
                Value<int> tableTo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TerracesCompanion.insert(
                code: code,
                tableFrom: tableFrom,
                tableTo: tableTo,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TerracesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TerracesTable,
      DbTerrace,
      $$TerracesTableFilterComposer,
      $$TerracesTableOrderingComposer,
      $$TerracesTableAnnotationComposer,
      $$TerracesTableCreateCompanionBuilder,
      $$TerracesTableUpdateCompanionBuilder,
      (DbTerrace, BaseReferences<_$AppDatabase, $TerracesTable, DbTerrace>),
      DbTerrace,
      PrefetchHooks Function()
    >;
typedef $$RemarksTableCreateCompanionBuilder =
    RemarksCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> itemId,
    });
typedef $$RemarksTableUpdateCompanionBuilder =
    RemarksCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> itemId,
    });

class $$RemarksTableFilterComposer
    extends Composer<_$AppDatabase, $RemarksTable> {
  $$RemarksTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemarksTableOrderingComposer
    extends Composer<_$AppDatabase, $RemarksTable> {
  $$RemarksTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemarksTable> {
  $$RemarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);
}

class $$RemarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemarksTable,
          DbRemark,
          $$RemarksTableFilterComposer,
          $$RemarksTableOrderingComposer,
          $$RemarksTableAnnotationComposer,
          $$RemarksTableCreateCompanionBuilder,
          $$RemarksTableUpdateCompanionBuilder,
          (DbRemark, BaseReferences<_$AppDatabase, $RemarksTable, DbRemark>),
          DbRemark,
          PrefetchHooks Function()
        > {
  $$RemarksTableTableManager(_$AppDatabase db, $RemarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> itemId = const Value.absent(),
              }) => RemarksCompanion(id: id, name: name, itemId: itemId),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> itemId = const Value.absent(),
              }) => RemarksCompanion.insert(id: id, name: name, itemId: itemId),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemarksTable,
      DbRemark,
      $$RemarksTableFilterComposer,
      $$RemarksTableOrderingComposer,
      $$RemarksTableAnnotationComposer,
      $$RemarksTableCreateCompanionBuilder,
      $$RemarksTableUpdateCompanionBuilder,
      (DbRemark, BaseReferences<_$AppDatabase, $RemarksTable, DbRemark>),
      DbRemark,
      PrefetchHooks Function()
    >;
typedef $$OrdersTableCreateCompanionBuilder =
    OrdersCompanion Function({
      Value<int> id,
      Value<int> orderTime,
      Value<String> userCode,
      Value<int> tableCode,
      Value<List<OrderItem>> items,
      Value<bool> pending,
      Value<bool> sent,
    });
typedef $$OrdersTableUpdateCompanionBuilder =
    OrdersCompanion Function({
      Value<int> id,
      Value<int> orderTime,
      Value<String> userCode,
      Value<int> tableCode,
      Value<List<OrderItem>> items,
      Value<bool> pending,
      Value<bool> sent,
    });

class $$OrdersTableFilterComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableFilterComposer({
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

  ColumnFilters<int> get orderTime => $composableBuilder(
    column: $table.orderTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userCode => $composableBuilder(
    column: $table.userCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tableCode => $composableBuilder(
    column: $table.tableCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<OrderItem>, List<OrderItem>, String>
  get items => $composableBuilder(
    column: $table.items,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get pending => $composableBuilder(
    column: $table.pending,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sent => $composableBuilder(
    column: $table.sent,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrdersTableOrderingComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableOrderingComposer({
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

  ColumnOrderings<int> get orderTime => $composableBuilder(
    column: $table.orderTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userCode => $composableBuilder(
    column: $table.userCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tableCode => $composableBuilder(
    column: $table.tableCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get items => $composableBuilder(
    column: $table.items,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pending => $composableBuilder(
    column: $table.pending,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sent => $composableBuilder(
    column: $table.sent,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrdersTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get orderTime =>
      $composableBuilder(column: $table.orderTime, builder: (column) => column);

  GeneratedColumn<String> get userCode =>
      $composableBuilder(column: $table.userCode, builder: (column) => column);

  GeneratedColumn<int> get tableCode =>
      $composableBuilder(column: $table.tableCode, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<OrderItem>, String> get items =>
      $composableBuilder(column: $table.items, builder: (column) => column);

  GeneratedColumn<bool> get pending =>
      $composableBuilder(column: $table.pending, builder: (column) => column);

  GeneratedColumn<bool> get sent =>
      $composableBuilder(column: $table.sent, builder: (column) => column);
}

class $$OrdersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrdersTable,
          DbOrder,
          $$OrdersTableFilterComposer,
          $$OrdersTableOrderingComposer,
          $$OrdersTableAnnotationComposer,
          $$OrdersTableCreateCompanionBuilder,
          $$OrdersTableUpdateCompanionBuilder,
          (DbOrder, BaseReferences<_$AppDatabase, $OrdersTable, DbOrder>),
          DbOrder,
          PrefetchHooks Function()
        > {
  $$OrdersTableTableManager(_$AppDatabase db, $OrdersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrdersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrdersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrdersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> orderTime = const Value.absent(),
                Value<String> userCode = const Value.absent(),
                Value<int> tableCode = const Value.absent(),
                Value<List<OrderItem>> items = const Value.absent(),
                Value<bool> pending = const Value.absent(),
                Value<bool> sent = const Value.absent(),
              }) => OrdersCompanion(
                id: id,
                orderTime: orderTime,
                userCode: userCode,
                tableCode: tableCode,
                items: items,
                pending: pending,
                sent: sent,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> orderTime = const Value.absent(),
                Value<String> userCode = const Value.absent(),
                Value<int> tableCode = const Value.absent(),
                Value<List<OrderItem>> items = const Value.absent(),
                Value<bool> pending = const Value.absent(),
                Value<bool> sent = const Value.absent(),
              }) => OrdersCompanion.insert(
                id: id,
                orderTime: orderTime,
                userCode: userCode,
                tableCode: tableCode,
                items: items,
                pending: pending,
                sent: sent,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrdersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrdersTable,
      DbOrder,
      $$OrdersTableFilterComposer,
      $$OrdersTableOrderingComposer,
      $$OrdersTableAnnotationComposer,
      $$OrdersTableCreateCompanionBuilder,
      $$OrdersTableUpdateCompanionBuilder,
      (DbOrder, BaseReferences<_$AppDatabase, $OrdersTable, DbOrder>),
      DbOrder,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$ArticlesTableTableManager get articles =>
      $$ArticlesTableTableManager(_db, _db.articles);
  $$ArticleGroupsTableTableManager get articleGroups =>
      $$ArticleGroupsTableTableManager(_db, _db.articleGroups);
  $$VenueTablesTableTableManager get venueTables =>
      $$VenueTablesTableTableManager(_db, _db.venueTables);
  $$TerracesTableTableManager get terraces =>
      $$TerracesTableTableManager(_db, _db.terraces);
  $$RemarksTableTableManager get remarks =>
      $$RemarksTableTableManager(_db, _db.remarks);
  $$OrdersTableTableManager get orders =>
      $$OrdersTableTableManager(_db, _db.orders);
}
