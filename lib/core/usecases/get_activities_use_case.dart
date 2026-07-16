import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/activity_summary.dart';
import 'package:furtive/core/repositories/activity_repository.dart';

/// Lightweight list of activities (stats only, no GPS points) for the list.
class GetActivitiesUseCase {
  final activityRepository = ActivityRepository();

  GetActivitiesUseCase();

  Future<List<ActivitySummary>> call() async {
    return await activityRepository.fetchSummaries();
  }
}

/// Full activity (with all points) by id — used when opening the detail page.
class GetActivityUseCase {
  final activityRepository = ActivityRepository();

  GetActivityUseCase();

  Future<ActivityEntity> call(String activityId) async {
    return await activityRepository.fetchSingle(activityId);
  }
}
