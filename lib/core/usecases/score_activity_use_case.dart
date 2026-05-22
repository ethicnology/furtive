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
      time: DateTime.now().toUtc(),
    );

    await activityRepository.score(activityId, [newPoint]);

    return newPoint;
  }
}
