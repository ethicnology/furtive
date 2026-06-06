import 'package:drift/drift.dart';

@DataClassName('ActivitiesRow')
// Indexed on startedAt because the activities list page sorts by it on
// every fetch; without the index the table scans the whole activities
// table on every refresh.
@TableIndex(name: 'idx_activities_started_at', columns: {#startedAt})
class Activities extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get stoppedAt => dateTime().nullable()();
  // Denormalised aggregates so the activities list can render distance/pace
  // without loading every point of every activity. -1 = not yet computed
  // (legacy rows backfilled lazily on first list fetch; live/in-progress rows
  // computed on the fly until ceased).
  RealColumn get distanceMeters =>
      real().withDefault(const Constant(-1))();
  IntColumn get activeDurationMs =>
      integer().withDefault(const Constant(-1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
