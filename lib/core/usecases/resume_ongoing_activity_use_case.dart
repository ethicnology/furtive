import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/repositories/activity_repository.dart';

/// Loads the activity the user was recording before the app was last closed
/// or killed (the newest row with `stoppedAt == null`), or null if there is
/// none. MapBloc calls this on init to rehydrate an in-progress run after a
/// cold start, so an OS process kill while the phone is locked no longer loses
/// the live activity from the UI.
class ResumeOngoingActivityUseCase {
  final activityRepository = ActivityRepository();

  ResumeOngoingActivityUseCase();

  Future<ActivityEntity?> call() async {
    return activityRepository.fetchOngoing();
  }
}
