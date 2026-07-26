import 'package:furtive/core/clock.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/entities/activity_summary.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/core/entities/activity_entity.dart';

/// Entity-level access to stored activities.
///
/// The layer boundary is deliberate and is the only one kept between blocs and
/// SQLite: [ActivityLocalDataSource] speaks drift/row types, this speaks
/// domain entities. The former pass-through use cases (CeaseActivity,
/// DeleteActivity, UpdateActivityName, ResumeOngoingActivity, GetActivities,
/// GetActivity, StartActivity) were aliases for one call each and are gone —
/// callers use these methods directly.
class ActivityRepository {
  /// [local] and [clock] default to real implementations so production call
  /// sites stay `ActivityRepository()`; tests inject fakes.
  ActivityRepository({ActivityLocalDataSource? local, Clock? clock})
    : local = local ?? ActivityLocalDataSource(clock: clock),
      _clock = clock ?? const SystemClock();

  final ActivityLocalDataSource local;
  final Clock _clock;

  Future<void> store(ActivityEntity activity) async {
    await local.store(ActivityModel.fromEntity(activity));
  }

  /// Creates and persists a fresh, in-progress activity (no `stoppedAt`).
  ///
  /// The id is the millisecond-precise ISO8601 creation instant; GPX import
  /// reuses the same convention so importing one file twice yields distinct
  /// ids.
  Future<ActivityEntity> startNew() async {
    final startedAt = _clock.nowUtc();
    final activity = ActivityEntity(
      id: startedAt.toIso8601String(),
      name: kDefaultActivityName,
      description: '',
      createdAt: startedAt,
      startedAt: startedAt,
      stoppedAt: null,
    );
    await store(activity);
    return activity;
  }

  /// Stats-only list for the activities page (no GPS points loaded).
  Future<List<ActivitySummary>> fetchSummaries({int? limit, int offset = 0}) {
    return local.fetchSummaries(limit: limit, offset: offset);
  }

  Future<ActivityEntity> fetchSingle(String activityId) async {
    return ActivityModel.toEntity(await local.fetchSingle(activityId));
  }

  /// The ongoing (never-ceased) activity with its points, or null. See
  /// [ActivityLocalDataSource.fetchOngoing].
  Future<ActivityEntity?> fetchOngoing() async {
    final model = await local.fetchOngoing();
    return model == null ? null : ActivityModel.toEntity(model);
  }

  Future<void> score(String activityId, List<ActivityPointEntity> points) {
    return local.score(
      activityId,
      points.map(ActivityPointModel.fromEntity).toList(),
    );
  }

  Future<void> cease(String activityId) => local.cease(activityId);

  Future<void> updateName(String activityId, String newName) =>
      local.updateName(activityId, newName);

  Future<void> delete(String activityId) => local.delete(activityId);
}
