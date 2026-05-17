import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/repositories/activity_repository.dart';

class StartActivityUseCase {
  final activityRepository = ActivityRepository();

  StartActivityUseCase();

  Future<ActivityEntity> call() async {
    final startedAt = DateTime.now().toUtc();
    final newActivity = ActivityEntity(
      id: startedAt.toIso8601String(),
      name: 'Track',
      description: '',
      createdAt: startedAt,
      startedAt: startedAt,
      stoppedAt: null,
    );

    await activityRepository.store(newActivity);
    return newActivity;
  }
}
