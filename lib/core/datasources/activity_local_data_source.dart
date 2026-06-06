import 'package:drift/drift.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/activity_summary.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/models/activity_model.dart';

class ActivityLocalDataSource {
  final db = getIt.get<LocalDatabase>();

  ActivityLocalDataSource();

  // Compute the denormalised aggregates the way the entity does (active
  // segments only, non-finite points filtered), so the list's stored values
  // match the detail page's live computation exactly.
  ({double distanceMeters, int durationMs}) _aggregates(
    List<ActivityPointModel> points,
  ) {
    // Filter to the exact set score() persists (finite lat/lon/elevation) so a
    // point with a NaN elevation can't make the stored aggregate disagree with
    // what the detail page recomputes from the persisted points.
    final finite =
        points
            .where(
              (p) =>
                  p.latitude.isFinite &&
                  p.longitude.isFinite &&
                  p.elevation.isFinite,
            )
            .toList();
    final entity = ActivityEntity(
      id: '',
      name: '',
      description: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      startedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      stoppedAt: null,
      points: finite.map(ActivityPointModel.toEntity).toList(),
    );
    return (
      distanceMeters: entity.activeDistanceMeters,
      durationMs: entity.activeDuration.inMilliseconds,
    );
  }

  Future<void> store(ActivityModel activity) async {
    // One transaction so a crash between the header insert and the point batch
    // can't leave a pointless header row (matters most for a large GPX import).
    // Completed/imported activities (stoppedAt set) store real aggregates.
    // An in-progress activity (just-started recording, stoppedAt null) stores
    // the -1 sentinel so fetchSummaries recomputes its stats live from points
    // until it's ceased — otherwise the list would show 0 km / 0:00 for the
    // active activity (and for any activity whose cease never ran after a crash).
    final agg = activity.stoppedAt != null
        ? _aggregates(activity.points)
        : (distanceMeters: -1.0, durationMs: -1);
    await db.transaction(() async {
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
              distanceMeters: Value(agg.distanceMeters),
              activeDurationMs: Value(agg.durationMs),
            ),
          );

      await score(activity.id, activity.points);
    });
  }

  Future<void> score(String activityId, List<ActivityPointModel> points) async {
    // Drop any non-finite fix before it reaches SQLite. A REAL column stores
    // NaN/Infinity as NULL, and latitude/longitude are non-nullable in the
    // model — so a single bad fix would make every later read of this
    // activity throw. The render layer also filters non-finite coords, but it
    // never runs if the read itself fails first.
    final finite =
        points
            .where(
              (p) =>
                  p.latitude.isFinite &&
                  p.longitude.isFinite &&
                  p.elevation.isFinite,
            )
            .toList();
    if (finite.isEmpty) return;
    // Batched insert: compile the statement once and run it for each point,
    // wrapped in an implicit transaction. Orders of magnitude faster than
    // N awaited inserts for long activities.
    await db.batch((batch) {
      batch.insertAll(
        db.activityPoints,
        finite.map(
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

    // Stamp stoppedAt and the denormalised aggregates together so the list
    // never sees a ceased activity with stale (-1) stats.
    final pointRows =
        await (db.select(db.activityPoints)
          ..where((t) => t.activityId.equals(activityId))).get();
    final agg = _aggregates(
      pointRows.map(ActivityPointModel.fromDatabase).toList(),
    );
    await (db.update(db.activities)..where((t) => t.id.equals(activityId)))
        .write(
          ActivitiesCompanion(
            stoppedAt: Value(DateTime.now().toUtc()),
            distanceMeters: Value(agg.distanceMeters),
            activeDurationMs: Value(agg.durationMs),
          ),
        );
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

  /// Lightweight list query: activities only (no point join), newest first,
  /// using the idx_activities_started_at index. Reads the denormalised
  /// distance/duration columns; for rows still at the -1 sentinel (legacy
  /// pre-v4 activities, or an in-progress activity) it computes from points
  /// once and — for ceased activities — persists the result so later loads
  /// stay cheap.
  Future<List<ActivitySummary>> fetchSummaries() async {
    final rows =
        await (db.select(db.activities)
              ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
            .get();

    final summaries = <ActivitySummary>[];
    for (final row in rows) {
      var distance = row.distanceMeters;
      var durationMs = row.activeDurationMs;

      if (distance < 0 || durationMs < 0) {
        final pointRows =
            await (db.select(db.activityPoints)
              ..where((t) => t.activityId.equals(row.id))).get();
        final agg = _aggregates(
          pointRows.map(ActivityPointModel.fromDatabase).toList(),
        );
        distance = agg.distanceMeters;
        durationMs = agg.durationMs;
        // Persist only for completed activities; an in-progress one keeps the
        // sentinel so it recomputes live until ceased.
        if (row.stoppedAt != null) {
          await (db.update(db.activities)..where((t) => t.id.equals(row.id)))
              .write(
                ActivitiesCompanion(
                  distanceMeters: Value(distance),
                  activeDurationMs: Value(durationMs),
                ),
              );
        }
      }

      summaries.add(
        ActivitySummary(
          id: row.id,
          name: row.name,
          startedAt: row.startedAt,
          activeDistanceMeters: distance,
          activeDuration: Duration(milliseconds: durationMs),
        ),
      );
    }
    return summaries;
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
