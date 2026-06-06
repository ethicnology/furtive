import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/activity_summary.dart';

part 'activities_state.mapper.dart';

@MappableClass()
class ActivitiesState with ActivitiesStateMappable {
  final List<ActivitySummary>? activities;
  final AppError? error;
  final bool isLoading;

  const ActivitiesState({this.activities, this.error, this.isLoading = false});
}
