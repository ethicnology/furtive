import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/repositories/location_repository.dart';

class ScoreActivityUseCase {
  final activityRepository = ActivityRepository();
  final locationRepository = LocationRepository();

  ScoreActivityUseCase();

  Future<ActivityPointEntity> call({
    required String activityId,
    required PositionEntity position,
    required ActivityPointStatusEntity status,
  }) async {
    final newPoint = ActivityPointEntity(
      position: position,
      status: status,
      // Prefer the GPS fix time; fall back to now() for synthesised positions
      // or platforms that don't report a fix timestamp.
      time: position.time ?? DateTime.now().toUtc(),
    );

    // Persist every fix immediately rather than buffering and batching. The
    // GPS cadence is ~0.2 fixes/sec (Android intervalDuration 5s), so there is
    // no write amplification to optimise away, and writing each fix as it
    // arrives means a crash / FGS kill never loses buffered points — the right
    // durability tradeoff for a tracker.
    await activityRepository.score(activityId, [newPoint]);

    return newPoint;
  }
}
