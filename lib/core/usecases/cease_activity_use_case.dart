import 'package:furtive/core/repositories/activity_repository.dart';

class CeaseActivityUseCase {
  final activityRepository = ActivityRepository();

  CeaseActivityUseCase();

  Future<void> call(String activityId) async {
    await activityRepository.cease(activityId);
  }
}
