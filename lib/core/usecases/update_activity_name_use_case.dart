import 'package:furtive/core/repositories/activity_repository.dart';

class UpdateActivityNameUseCase {
  final _activityRepository = ActivityRepository();

  UpdateActivityNameUseCase();

  Future<void> call(String activityId, String newName) async {
    await _activityRepository.updateName(activityId, newName);
  }
}
