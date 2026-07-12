import 'package:furtive/core/repositories/activity_repository.dart';

class DeleteActivityUseCase {
  final _activityRepository = ActivityRepository();

  DeleteActivityUseCase();

  Future<void> call(String activityId) async {
    await _activityRepository.delete(activityId);
  }
}
