import 'package:drift/drift.dart';
import 'package:furtive/core/database/tables/activities_table.dart';
import 'package:furtive/core/entities/activity_entity.dart';

@DataClassName('ActivityPointsRow')
@TableIndex(name: 'idx_activity_points_activity_id', columns: {#activityId})
class ActivityPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get elevation => real()();
  DateTimeColumn get time => dateTime()();
  TextColumn get activityId => text().references(Activities, #id)();
  TextColumn get status => textEnum<ActivityPointsStatusColumn>()();
  // GPS fix quality (v5). Nullable: null for points recorded before this
  // column existed, for GPX imports, and for any provider/platform that
  // doesn't report the field — never backfilled, callers must treat null as
  // "unknown" rather than "perfect fix". See PositionEntity.accuracy /
  // .verticalAccuracy and GpsQualityFilter / the elevation-gain smoothing in
  // activity_entity.dart. docs/AUDIT-2026-07.md §4.
  RealColumn get accuracy => real().nullable()();
  RealColumn get verticalAccuracy => real().nullable()();
}

// `signalLost` added without a schema migration on purpose: drift's textEnum
// stores the enum *name* in a plain TEXT column with no CHECK constraint,
// so a new value changes no DDL — old rows keep reading fine and new rows
// simply store the new name. Only a downgrade to an older APK would choke
// on it (unsupported anyway). See ActivityPointStatusEntity.signalLost for
// the semantics.
enum ActivityPointsStatusColumn {
  active,
  paused,
  signalLost;

  static ActivityPointsStatusColumn fromEntity(
    ActivityPointStatusEntity status,
  ) {
    switch (status) {
      case ActivityPointStatusEntity.active:
        return ActivityPointsStatusColumn.active;
      case ActivityPointStatusEntity.paused:
        return ActivityPointsStatusColumn.paused;
      case ActivityPointStatusEntity.signalLost:
        return ActivityPointsStatusColumn.signalLost;
    }
  }

  ActivityPointStatusEntity toEntity() {
    switch (this) {
      case ActivityPointsStatusColumn.active:
        return ActivityPointStatusEntity.active;
      case ActivityPointsStatusColumn.paused:
        return ActivityPointStatusEntity.paused;
      case ActivityPointsStatusColumn.signalLost:
        return ActivityPointStatusEntity.signalLost;
    }
  }
}
