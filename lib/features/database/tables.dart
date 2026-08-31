import 'package:drift/drift.dart';

import 'converters.dart';

/// drift table definitions — the local cache of downloaded master data plus the
/// offline order queue. Mirrors the reference client's Room entities
/// (`LocalUser`, `LocalItem`, `LocalGroup`, `LocalTable`, `LocalTerrace`,
/// `LocalOrder`, `LocalRemark`).
///
/// Generated data classes are prefixed `Db*` (via [DataClassName]) so they
/// don't collide with the plain-Dart domain models of the same name (`User`,
/// `Article`, …). Repositories map between the two.

@DataClassName('DbUser')
class Users extends Table {
  TextColumn get code => text()();
  TextColumn get username => text().withDefault(const Constant(''))();
  IntColumn get pin => integer().withDefault(const Constant(0))();
  BoolColumn get changeQuantityRight =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get allTablesOpenRight =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get deleteRight => boolean().withDefault(const Constant(false))();
  BoolColumn get superuser => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {code};
}

@DataClassName('DbArticle')
class Articles extends Table {
  IntColumn get code => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  RealColumn get price => real().withDefault(const Constant(0))();
  TextColumn get unit => text().withDefault(const Constant(''))();
  TextColumn get groupCode => text().withDefault(const Constant(''))();
  IntColumn get orderNo =>
      integer().named('order_num').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}

@DataClassName('DbArticleGroup')
class ArticleGroups extends Table {
  TextColumn get code => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get orderNo =>
      integer().named('order_num').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}

@DataClassName('DbVenueTable')
class VenueTables extends Table {
  IntColumn get code => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get userCode => text().withDefault(const Constant(''))();
  IntColumn get itemCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}

@DataClassName('DbTerrace')
class Terraces extends Table {
  TextColumn get code => text()();
  IntColumn get tableFrom => integer().withDefault(const Constant(0))();
  IntColumn get tableTo => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}

@DataClassName('DbRemark')
class Remarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get itemId => integer().withDefault(const Constant(0))();
}

@DataClassName('DbOrder')
class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderTime => integer().withDefault(const Constant(0))();
  TextColumn get userCode => text().withDefault(const Constant(''))();
  IntColumn get tableCode => integer().withDefault(const Constant(0))();
  TextColumn get items =>
      text().map(const OrderItemListConverter()).withDefault(
            const Constant('[]'),
          )();
  BoolColumn get pending => boolean().withDefault(const Constant(false))();
  BoolColumn get sent => boolean().withDefault(const Constant(false))();
}
