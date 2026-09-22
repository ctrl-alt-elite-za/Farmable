/// The local schema.
///
/// Every table here mirrors a table in
/// `apps/backend/src/farmable_backend/models.py`, column for column, so that
/// wiring the real API later is a swap rather than a rewrite. Two things are
/// deliberately different and both are called out where they occur:
///
/// * **Ids are `TEXT`, not `UUID`.** SQLite has no UUID type. The values are
///   canonical UUID strings, so they round-trip to the server's `Uuid`
///   columns unchanged.
/// * **Decimals are `TEXT`.** `area_m2` is `Numeric(14, 2)` on the server and
///   serialises as a *string* with significant trailing zeros. Storing it as a
///   double here is how `"6000.00"` becomes `6000.0` and a contract test
///   starts failing for no visible reason.
///
/// Money is always an integer count of cents. Never a double.
///
/// Columns with no server counterpart are marked LOCAL-ONLY, with the reason.
/// The session report lists them together as the migration they imply.
library;

import 'package:drift/drift.dart';

/// The bookkeeping every owned record carries on the server:
/// `version`, `sync_state`, `deleted_at` and the two timestamps.
///
/// `deleted_at` makes deletes soft, which is what lets a delete performed
/// offline sync later instead of vanishing with the row.
mixin OwnedRecord on Table {
  TextColumn get id => text()();
  TextColumn get farmId => text()();
  TextColumn get ownerId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// `users`. Only the farmer's own row exists locally.
class Users extends Table {
  TextColumn get id => text()();

  /// LOCAL-ONLY. The server's `users` table carries no name — auth is not
  /// built yet (#9). Home opens with "Hello, Sipho", and a greeting is the
  /// one place the product cannot be anonymous.
  TextColumn get displayName => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `farms`.
class Farms extends Table with OwnedRecord {
  TextColumn get name => text()();

  /// LOCAL-ONLY. "KwaMashu, KwaZulu-Natal". `farms` has no place column.
  TextColumn get locality => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `sections`.
class Sections extends Table with OwnedRecord {
  TextColumn get name => text()();

  /// GeoJSON, as the server stores it (`JSON` / `JSONB`). Held as text
  /// because nothing on these two screens reads the geometry — the map
  /// preview draws from it, and parsing happens there, once.
  TextColumn get boundary => text().nullable()();

  /// `Numeric(14, 2)` on the server. See the library comment.
  TextColumn get areaM2 => text().nullable()();

  /// How the area was arrived at — `demo_api`'s `area_source`. The production
  /// `sections` table has no such column yet; the design surfaces it because
  /// a farmer-supplied number and a walked boundary deserve different
  /// confidence.
  TextColumn get areaSource => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `plantings`.
class Plantings extends Table with OwnedRecord {
  TextColumn get sectionId => text()();

  /// Free text on the server, so free text here. The `demo_api` `Crop` enum
  /// is cabbage and spinach only and cannot hold the demo's Tomato Section.
  TextColumn get crop => text()();

  /// LOCAL-ONLY. "Star 3306" — the design names the cultivar.
  TextColumn get variety => text().nullable()();

  DateTimeColumn get plantedOn => dateTime().nullable()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `observations`.
class Observations extends Table with OwnedRecord {
  TextColumn get sectionId => text()();
  TextColumn get type => text()();
  TextColumn get note => text()();
  TextColumn get healthStatus => text().nullable()();
  TextColumn get actionTaken => text().nullable()();
  TextColumn get localMediaId => text().nullable()();
  BoolColumn get createdByVoice =>
      boolean().withDefault(const Constant(false))();

  /// LOCAL-ONLY. The gauge is a number out of 100; `health_status` is a word.
  IntColumn get healthScore => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `farm_tasks`.
class FarmTasks extends Table with OwnedRecord {
  TextColumn get sectionId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  /// `Date` on the server. Stored at local midnight; nothing reads a time.
  DateTimeColumn get dueDate => dateTime()();

  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get expectedCostCents => integer().nullable()();

  /// LOCAL-ONLY. The `saved_plans` row whose acceptance generated this step,
  /// or null for a task a person created.
  ///
  /// The server's `farm_tasks` has no such column, and the distinction it
  /// carries is not cosmetic: accepting a new plan retires the schedule the
  /// last one generated, and it has to be able to tell those steps apart from
  /// the reminder the farmer typed themselves. Without it the choice is
  /// between leaving two schedules on the timeline and deleting the farmer's
  /// own reminder, and both are wrong.
  TextColumn get planId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `financial_records`.
class FinancialRecords extends Table with OwnedRecord {
  TextColumn get sectionId => text().nullable()();
  TextColumn get type => text()();
  TextColumn get category => text()();
  IntColumn get amountCents => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `saved_plans`. Carried so an approved plan survives offline; the planner
/// screens that write it are not part of this session.
class SavedPlans extends Table with OwnedRecord {
  TextColumn get sectionId => text()();
  TextColumn get status => text().withDefault(const Constant('saved'))();

  /// The planner result, verbatim. Stored as the JSON text the server stores,
  /// not as parsed columns, so nothing is lost on the way back up.
  TextColumn get plan => text()();

  DateTimeColumn get approvedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// LOCAL-ONLY table, but **not** local-only data.
///
/// A materialised read of the numbers inside `saved_plans.plan` for the
/// section's approved plan: projected profit, projected cost and the harvest
/// window. Parsing a planner result inside a build method is the alternative,
/// and the plan changes far less often than the screen rebuilds.
class SectionProjections extends Table {
  TextColumn get sectionId => text()();
  IntColumn get expectedProfitCents => integer()();
  IntColumn get expectedCostCents => integer()();

  /// Harvest is a window, not a day count. "92 days" is derived from
  /// [harvestStart] at render time and is never stored.
  DateTimeColumn get harvestStart => dateTime()();
  DateTimeColumn get harvestEnd => dateTime()();

  TextColumn get planId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sectionId};
}

/// LOCAL-ONLY table. The descriptive copy Zone Detail shows (guide §23, §24)
/// for which `sections` has no columns at all.
class SectionDetails extends Table {
  TextColumn get sectionId => text()();
  TextColumn get description => text().nullable()();
  TextColumn get waterNote => text().nullable()();
  TextColumn get soilNote => text().nullable()();
  TextColumn get marketNote => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sectionId};
}

/// The outbox.
///
/// The server's `sync_mutations` is its idempotency ledger: one row per
/// `mutation_id`, so replaying a mutation cannot create a second record. This
/// table is the client half of that contract — every local write records the
/// mutation id it will be sent under, generated once, here, and reused for
/// every retry including retries after the app restarts.
///
/// That is what makes "syncing the same local mutation twice creates one
/// server record" true by construction rather than by luck.
class SyncMutations extends Table {
  TextColumn get mutationId => text()();
  TextColumn get farmId => text()();
  TextColumn get ownerId => text()();
  TextColumn get operation => text()();
  TextColumn get recordType => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Null until the server has acknowledged it. The count of nulls is what
  /// "3 changes waiting" shows.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {mutationId};
}

/// Single-row table recording that the demo seed has run.
///
/// Seeding keys off this rather than off "are there any sections?", so a
/// farmer who deletes every section does not get the demo farm poured back
/// over their empty one on the next launch.
class SeedState extends Table {
  IntColumn get id => integer()();
  TextColumn get seedVersion => text()();
  DateTimeColumn get seededAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
