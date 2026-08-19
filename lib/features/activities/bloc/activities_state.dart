import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/activity_summary.dart';

part 'activities_state.mapper.dart';

enum ActivityImportStatus { idle, inProgress, success, failure }

@MappableClass()
class ActivitiesState with ActivitiesStateMappable {
  final List<ActivitySummary>? activities;
  final AppError? error;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final ActivityImportStatus importStatus;

  const ActivitiesState({
    this.activities,
    this.error,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.importStatus = ActivityImportStatus.idle,
  });
}
