import 'package:drift/drift.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/activity_summary.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/models/activity_model.dart';

class ActivityLocalDataSource {
  /// [db] and [clock] default to the app-wide singleton / real clock, so
  /// production call sites stay `ActivityLocalDataSource()`. Tests inject an
  /// in-memory database and a [FixedClock] to drive the stale-activity window
  /// (see [ongoingStaleAfter]) without waiting 12 real hours.
  ActivityLocalDataSource({LocalDatabase? db, Clock? clock})
    : db = db ?? getIt.get<LocalDatabase>(),
      _clock = clock ?? const SystemClock();

  final LocalDatabase db;
  final Clock _clock;

  // Compute the denormalised aggregates the way the entity does (active
  // segments only, non-finite points filtered), so the list's stored values
  // match the detail page's live computation exactly.
  ({double distanceMeters, int durationMs}) _aggregates(
    List<ActivityPointModel> points,
  ) {
    // Filter to the exact set score() persists (finite, in-range lat/lon,
    // finite elevation) so a point with a NaN elevation or an out-of-range
    // coordinate can't make the stored aggregate disagree with what the
    // detail page recomputes from the persisted points.
    final finite = points
        .where(
          (p) =>
              p.latitude.isFinite &&
              p.latitude >= -90 &&
              p.latitude <= 90 &&
              p.longitude.isFinite &&
              p.longitude >= -180 &&
              p.longitude <= 180 &&
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

      // Points inserted alongside the header row belong to it by construction
      // (new recording or GPX import), so skip the ongoing-guard which would
      // reject an import whose stoppedAt is already stamped.
      await score(activity.id, activity.points, enforceOngoing: false);
    });
  }

  /// Persists GPS fixes for [activityId].
  ///
  /// [enforceOngoing] (default true) rejects the write inside a transaction if
  /// the activity is already ceased (`stoppedAt != null`) or gone. This closes
  /// the score-after-cease race: bloc handlers run concurrently, so a
  /// ScoreActivity that passed its in-memory null-check can otherwise be
  /// ordered *after* cease()'s transaction and land a point past stoppedAt —
  /// leaving the stored aggregates permanently short of a point that is in the
  /// DB. With the guard, such a late point is dropped rather than corrupting
  /// the stored-vs-live agreement. Set false only from store(), where the
  /// header row is inserted in the same transaction.
  Future<void> score(
    String activityId,
    List<ActivityPointModel> points, {
    bool enforceOngoing = true,
  }) async {
    // Drop any non-finite fix before it reaches SQLite. A REAL column stores
    // NaN/Infinity as NULL, and latitude/longitude are non-nullable in the
    // model — so a single bad fix would make every later read of this
    // activity throw. The render layer also filters non-finite coords, but it
    // never runs if the read itself fails first.
    //
    // Also enforce the WGS84 range, matching the GPX import validation
    // (gpx.dart) — this was the one entry point that only checked `isFinite`
    // and let an out-of-range fix (e.g. a defective platform location like
    // lat=200) through to storage, where it would silently poison
    // Geolocator.distanceBetween-based aggregates.
    final finite = points
        .where(
          (p) =>
              p.latitude.isFinite &&
              p.latitude >= -90 &&
              p.latitude <= 90 &&
              p.longitude.isFinite &&
              p.longitude >= -180 &&
              p.longitude <= 180 &&
              p.elevation.isFinite,
        )
        .toList();
    if (finite.isEmpty) return;

    Future<void> insert() async {
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
              accuracy: Value(point.accuracy),
              verticalAccuracy: Value(point.verticalAccuracy),
            ),
          ),
        );
      });
    }

    if (!enforceOngoing) {
      await insert();
      return;
    }

    // Read the stoppedAt flag and insert atomically so a cease() can't slip
    // between the check and the write.
    await db.transaction(() async {
      final row = await (db.select(
        db.activities,
      )..where((t) => t.id.equals(activityId))).getSingleOrNull();
      if (row == null || row.stoppedAt != null) {
        // Activity ceased or deleted while this fix was queued — drop it.
        return;
      }
      await insert();
    });
  }

  /// Stamps [activityId] as stopped and persists its final aggregates.
  ///
  /// [stoppedAt] defaults to now — the deliberate-stop path (user taps Stop)
  /// wants the stop wall-clock. The auto-cease paths in [fetchOngoing] pass
  /// the timestamp of the last recorded fix instead, so an activity
  /// abandoned days ago (found stale on the next cold start) doesn't get a
  /// `stoppedAt` days later than its last real data point — every consumer
  /// of `stoppedAt` (the detail page's elapsed time, list sort order, a
  /// future export) would otherwise see a misleadingly long "duration".
  ///
  /// Idempotent: ceasing an already-stopped activity is a silent no-op
  /// rather than throwing. The only two callers are MapBloc (already
  /// guarded in-memory against a double user-tap before it ever calls this)
  /// and fetchOngoing's orphan reconciliation, which must tolerate a
  /// concurrent/repeat cease of the same row without surfacing an
  /// AppError that would abort the whole resume flow.
  Future<void> cease(String activityId, {DateTime? stoppedAt}) async {
    // One transaction so the point-read, aggregate compute and the stoppedAt +
    // aggregate write are atomic. Without it, a score() insert from a GPS fix
    // still in flight when the user taps Stop can land between the read and the
    // write, leaving the stored aggregate short of a point that IS in the DB —
    // the exact stored-vs-live divergence the denormalisation tries to avoid.
    await db.transaction(() async {
      final activity = await (db.select(
        db.activities,
      )..where((t) => t.id.equals(activityId))).getSingleOrNull();

      if (activity == null) throw AppError('Activity not found');
      if (activity.stoppedAt != null) return;

      // Stamp stoppedAt and the denormalised aggregates together so the list
      // never sees a ceased activity with stale (-1) stats. Ordered by id
      // (insertion order): _aggregates ultimately segments by a STABLE sort
      // that relies on ties (same-second timestamps, notably the ±1µs
      // signalLost boundary pairs — truncated to whole seconds by SQLite)
      // being broken by this input order, not an arbitrary one.
      final pointRows =
          await (db.select(db.activityPoints)
                ..where((t) => t.activityId.equals(activityId))
                ..orderBy([(t) => OrderingTerm.asc(t.id)]))
              .get();
      final agg = _aggregates(
        pointRows.map(ActivityPointModel.fromDatabase).toList(),
      );
      await (db.update(
        db.activities,
      )..where((t) => t.id.equals(activityId))).write(
        ActivitiesCompanion(
          stoppedAt: Value(stoppedAt ?? _clock.nowUtc()),
          distanceMeters: Value(agg.distanceMeters),
          activeDurationMs: Value(agg.durationMs),
        ),
      );
    });
  }

  /// Beyond this since the last recorded fix, an ongoing (never-ceased)
  /// activity is considered abandoned rather than resumable — a cease() that
  /// crashed, or a kill so old the user has moved on. Resuming it would show a
  /// bogus multi-hour/day "live" run with a runaway timer. Such activities are
  /// auto-ceased (finalised with real aggregates) instead of resumed.
  static const ongoingStaleAfter = Duration(hours: 12);

  /// The most recently started activity that was never ceased
  /// (`stoppedAt == null`), with its points — or null if none resumable. Used
  /// to resume a recording the user started before the OS killed the app
  /// process (Doze / aggressive OEM battery management) so reopening the app
  /// restores the ongoing run instead of cold-starting to a blank map. Points
  /// are written on every fix, so whatever survived the kill is here.
  ///
  /// Reconciles orphans first: if repeated kills left several `stoppedAt IS
  /// NULL` rows, only the newest is a resume candidate — every older one is
  /// auto-ceased so it stops being "in progress" forever (and stops forcing
  /// fetchSummaries to recompute its aggregates on every list open). The
  /// newest candidate is itself auto-ceased (and null returned) when its last
  /// fix is older than [ongoingStaleAfter].
  Future<ActivityModel?> fetchOngoing() async {
    final ongoing =
        await (db.select(db.activities)
              ..where((t) => t.stoppedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
            .get();
    if (ongoing.isEmpty) return null;

    // Auto-cease every orphan except the newest candidate, stamped with
    // each orphan's own last fix (see cease()'s stoppedAt doc) rather than
    // "now" — an orphan abandoned days ago must not report a multi-day
    // "duration" just because that's when the reconciliation happened to
    // run.
    for (final orphan in ongoing.skip(1)) {
      final orphanPoints =
          await (db.select(db.activityPoints)
                ..where((t) => t.activityId.equals(orphan.id))
                ..orderBy([(t) => OrderingTerm.asc(t.id)]))
              .get();
      final orphanLastFix = orphanPoints.isEmpty
          ? orphan.startedAt
          : orphanPoints
                .map((p) => p.time)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      await cease(orphan.id, stoppedAt: orphanLastFix);
    }

    final candidate = ongoing.first;
    final points =
        await (db.select(db.activityPoints)
              ..where((t) => t.activityId.equals(candidate.id))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();

    // Stale check against the last fix (fall back to startedAt if pointless).
    final lastFix = points.isEmpty
        ? candidate.startedAt
        : points.map((p) => p.time).reduce((a, b) => a.isAfter(b) ? a : b);
    if (_clock.nowUtc().difference(lastFix.toUtc()) > ongoingStaleAfter) {
      await cease(candidate.id, stoppedAt: lastFix);
      return null;
    }

    return ActivityModel.fromDatabase(candidate, points);
  }

  Future<ActivityModel> fetchSingle(String activityId) async {
    final activity = await (db.select(
      db.activities,
    )..where((t) => t.id.equals(activityId))).getSingleOrNull();
    if (activity == null) throw AppError('Activity not found');

    final points =
        await (db.select(db.activityPoints)
              ..where((t) => t.activityId.equals(activityId))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();

    return ActivityModel.fromDatabase(activity, points);
  }

  /// Lightweight list query: activities only (no point join), newest first,
  /// using the idx_activities_started_at index. Reads the denormalised
  /// distance/duration columns; for rows still at the -1 sentinel (legacy
  /// pre-v4 activities, or an in-progress activity) it computes from points
  /// once and — for ceased activities — persists the result so later loads
  /// stay cheap.
  ///
  /// [limit]/[offset] page the query. Unbounded by default for callers that
  /// genuinely want everything, but the activities list passes a page size:
  /// without one, every open of that screen read EVERY activity row, and
  /// re-materialised every point of any row still on the sentinel — for an
  /// in-progress 24 h recording that is ~17k rows rebuilt on each visit,
  /// because an in-progress row deliberately never persists its aggregates.
  Future<List<ActivitySummary>> fetchSummaries({
    int? limit,
    int offset = 0,
  }) async {
    final query = db.select(db.activities)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (limit != null) query.limit(limit, offset: offset);
    final rows = await query.get();

    final summaries = <ActivitySummary>[];
    for (final row in rows) {
      var distance = row.distanceMeters;
      var durationMs = row.activeDurationMs;

      if (distance < 0 || durationMs < 0) {
        // Ordered by id — see the identical comment in cease() above.
        final pointRows =
            await (db.select(db.activityPoints)
                  ..where((t) => t.activityId.equals(row.id))
                  ..orderBy([(t) => OrderingTerm.asc(t.id)]))
                .get();
        final agg = _aggregates(
          pointRows.map(ActivityPointModel.fromDatabase).toList(),
        );
        distance = agg.distanceMeters;
        durationMs = agg.durationMs;
        // Persist only for completed activities; an in-progress one keeps the
        // sentinel so it recomputes live until ceased.
        if (row.stoppedAt != null) {
          await (db.update(
            db.activities,
          )..where((t) => t.id.equals(row.id))).write(
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
    final activity = await (db.select(
      db.activities,
    )..where((t) => t.id.equals(activityId))).getSingleOrNull();

    if (activity == null) throw AppError('Activity not found');

    await (db.update(db.activities)..where((t) => t.id.equals(activityId)))
        .write(ActivitiesCompanion(name: Value(newName)));
  }

  Future<void> delete(String activityId) async {
    // Wrap both deletes in a transaction so a crash or stream-close between
    // them can't leave orphan activity_points rows pointing at a missing
    // activity. SQLite-level cascade isn't declared on the FK either.
    await db.transaction(() async {
      final activity = await (db.select(
        db.activities,
      )..where((t) => t.id.equals(activityId))).getSingleOrNull();

      if (activity == null) throw AppError('Activity not found');

      await (db.delete(
        db.activityPoints,
      )..where((t) => t.activityId.equals(activityId))).go();

      await (db.delete(
        db.activities,
      )..where((t) => t.id.equals(activityId))).go();
    });
  }
}
