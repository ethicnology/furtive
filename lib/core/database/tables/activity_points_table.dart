import 'package:drift/drift.dart';
import 'package:furtive/core/database/tables/activities_table.dart';
import 'package:furtive/core/entities/activity_entity.dart';

@DataClassName('ActivityPointsRow')
class ActivityPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get elevation => real()();
  DateTimeColumn get time => dateTime()();
  TextColumn get activityId => text().references(Activities, #id)();
  TextColumn get status => textEnum<ActivityPointsStatusColumn>()();
}

enum ActivityPointsStatusColumn {
  active,
  paused;

  static ActivityPointsStatusColumn fromEntity(
    ActivityPointStatusEntity status,
  ) {
    switch (status) {
      case ActivityPointStatusEntity.active:
        return ActivityPointsStatusColumn.active;
      case ActivityPointStatusEntity.paused:
        return ActivityPointsStatusColumn.paused;
    }
  }

  ActivityPointStatusEntity toEntity() {
    switch (this) {
      case ActivityPointsStatusColumn.active:
        return ActivityPointStatusEntity.active;
      case ActivityPointsStatusColumn.paused:
        return ActivityPointStatusEntity.paused;
    }
  }
}
