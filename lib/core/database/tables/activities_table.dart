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

  @override
  Set<Column<Object>> get primaryKey => {id};
}
