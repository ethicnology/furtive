import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/repositories/activity_repository.dart';

class ScoreActivityUseCase {
  ScoreActivityUseCase({ActivityRepository? activities, Clock? clock})
    : _activities = activities ?? ActivityRepository(clock: clock),
      _clock = clock ?? const SystemClock();

  final ActivityRepository _activities;
  final Clock _clock;

  /// Persists the new fix and returns every point written (in order). When
  /// [gapFrom] is set — the last recorded point before a detected GPS outage
  /// (see SignalGapDetector in MapBloc) — the gap is bracketed with two
  /// `signalLost` boundary points written in the same batch as the fix:
  /// a duplicate of [gapFrom] 1µs after it, and a duplicate of the new fix
  /// 1µs before it. The bracketed span becomes its own signalLost segment
  /// carrying the outage duration, keeping it out of the active stats and
  /// off the solid polyline (same duplicated-boundary mechanic as the GPX
  /// import's `<trkseg>` handling).
  Future<List<ActivityPointEntity>> call({
    required String activityId,
    required PositionEntity position,
    required ActivityPointStatusEntity status,
    ActivityPointEntity? gapFrom,
  }) async {
    final newPoint = ActivityPointEntity(
      position: position,
      status: status,
      // Prefer the GPS fix time; fall back to now() for synthesised positions
      // or platforms that don't report a fix timestamp.
      time: position.time ?? _clock.nowUtc(),
    );

    final points = <ActivityPointEntity>[
      if (gapFrom != null) ...[
        ActivityPointEntity(
          position: gapFrom.position,
          time: gapFrom.time.add(const Duration(microseconds: 1)),
          status: ActivityPointStatusEntity.signalLost,
        ),
        ActivityPointEntity(
          position: newPoint.position,
          time: newPoint.time.subtract(const Duration(microseconds: 1)),
          status: ActivityPointStatusEntity.signalLost,
        ),
      ],
      newPoint,
    ];

    // Persist every fix immediately rather than buffering and batching. The
    // GPS cadence is ~0.2 fixes/sec (Android intervalDuration 5s), so there is
    // no write amplification to optimise away, and writing each fix as it
    // arrives means a crash / FGS kill never loses buffered points — the right
    // durability tradeoff for a tracker.
    await _activities.score(activityId, points);

    return points;
  }
}
