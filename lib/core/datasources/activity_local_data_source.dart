import 'package:drift/drift.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/models/activity_model.dart';

class ActivityLocalDataSource {
  final db = getIt.get<LocalDatabase>();

  ActivityLocalDataSource();

  Future<void> store(ActivityModel activity) async {
    await db
        .into(db.activities)
        .insert(
          ActivitiesCompanion(
            id: Value(activity.id),
            name: Value(activity.name),
            description: Value(activity.description),
            createdAt: Value(activity.createdAt),
            startedAt: Value(activity.startedAt),
            stoppedAt: Value(activity.stoppedAt),
          ),
        );

    await score(activity.id, activity.points);
  }

  Future<void> score(String activityId, List<ActivityPointModel> points) async {
    if (points.isEmpty) return;
    // Batched insert: compile the statement once and run it for each point,
    // wrapped in an implicit transaction. Orders of magnitude faster than
    // N awaited inserts for long activities.
    await db.batch((batch) {
      batch.insertAll(
        db.activityPoints,
        points.map(
          (point) => ActivityPointsCompanion(
            activityId: Value(activityId),
            latitude: Value(point.latitude),
            longitude: Value(point.longitude),
            elevation: Value(point.elevation),
            time: Value(point.time),
            status: Value(point.status),
          ),
        ),
      );
    });
  }

  Future<void> cease(String activityId) async {
    // if stoppedAt is not null, throw an error
    final activity =
        await (db.select(db.activities)
          ..where((t) => t.id.equals(activityId))).getSingleOrNull();

    if (activity == null) throw AppError('Activity not found');
    if (activity.stoppedAt != null) throw AppError('Activity already stopped');

    await (db.update(db.activities)..where(
      (t) => t.id.equals(activityId),
    )).write(ActivitiesCompanion(stoppedAt: Value(DateTime.now().toUtc())));
  }

  Future<ActivityModel> fetchSingle(String activityId) async {
    final activity =
        await (db.select(db.activities)
          ..where((t) => t.id.equals(activityId))).getSingleOrNull();
    if (activity == null) throw AppError('Activity not found');

    final points =
        await (db.select(db.activityPoints)
          ..where((t) => t.activityId.equals(activityId))).get();

    return ActivityModel.fromDatabase(activity, points);
  }

  Future<List<ActivityModel>> fetch() async {
    final query = db.select(db.activities).join([
      leftOuterJoin(
        db.activityPoints,
        db.activityPoints.activityId.equalsExp(db.activities.id),
      ),
    ]);

    final results = await query.get();
    final activityMap = <String, ActivityModel>{};

    for (final row in results) {
      final activity = row.readTable(db.activities);
      final point = row.readTableOrNull(db.activityPoints);

      activityMap.putIfAbsent(
        activity.id.toString(),
        () => ActivityModel.fromDatabase(activity, []),
      );

      if (point != null) {
        activityMap[activity.id]!.points.add(
          ActivityPointModel.fromDatabase(point),
        );
      }
    }

    for (final activity in activityMap.values) {
      // sort points by time
      activity.points.sort((a, b) => a.time.compareTo(b.time));
    }

    final activities = activityMap.values.toList();
    activities.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return activities;
  }

  Future<void> updateName(String activityId, String newName) async {
    final activity =
        await (db.select(db.activities)
          ..where((t) => t.id.equals(activityId))).getSingleOrNull();

    if (activity == null) throw AppError('Activity not found');

    await (db.update(db.activities)..where(
      (t) => t.id.equals(activityId),
    )).write(ActivitiesCompanion(name: Value(newName)));
  }

  Future<void> delete(String activityId) async {
    // Wrap both deletes in a transaction so a crash or stream-close between
    // them can't leave orphan activity_points rows pointing at a missing
    // activity. SQLite-level cascade isn't declared on the FK either.
    await db.transaction(() async {
      final activity =
          await (db.select(db.activities)
            ..where((t) => t.id.equals(activityId))).getSingleOrNull();

      if (activity == null) throw AppError('Activity not found');

      await (db.delete(db.activityPoints)
        ..where((t) => t.activityId.equals(activityId))).go();

      await (db.delete(db.activities)
        ..where((t) => t.id.equals(activityId))).go();
    });
  }
}
