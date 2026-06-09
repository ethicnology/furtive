import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/entities/activity_summary.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/core/entities/activity_entity.dart';

class ActivityRepository {
  final localActivities = ActivityLocalDataSource();

  ActivityRepository();

  Future<void> store(ActivityEntity activity) async {
    final model = ActivityModel.fromEntity(activity);
    await localActivities.store(model);
  }

  Future<List<ActivitySummary>> fetchSummaries() async {
    return await localActivities.fetchSummaries();
  }

  Future<ActivityEntity> fetchSingle(String activityId) async {
    final model = await localActivities.fetchSingle(activityId);
    return ActivityModel.toEntity(model);
  }

  /// The ongoing (never-ceased) activity with its points, or null. See
  /// ActivityLocalDataSource.fetchOngoing.
  Future<ActivityEntity?> fetchOngoing() async {
    final model = await localActivities.fetchOngoing();
    if (model == null) return null;
    return ActivityModel.toEntity(model);
  }

  Future<void> score(
    String activityId,
    List<ActivityPointEntity> points,
  ) async {
    final models = points.map(ActivityPointModel.fromEntity).toList();
    await localActivities.score(activityId, models);
  }

  Future<void> cease(String activityId) async {
    await localActivities.cease(activityId);
  }

  Future<void> updateName(String activityId, String newName) async {
    await localActivities.updateName(activityId, newName);
  }

  Future<void> delete(String activityId) async {
    await localActivities.delete(activityId);
  }
}
