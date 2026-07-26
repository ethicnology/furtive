import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/activity_summary.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/usecases/import_activity_from_gpx_use_case.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:furtive/features/activities/bloc/activities_state.dart';

/// How many activities the list loads at a time. See
/// ActivityLocalDataSource.fetchSummaries for why an unbounded read was a
/// problem. 50 comfortably fills any phone screen; the list requests the next
/// page as the user scrolls.
const int kActivitiesPageSize = 50;

class ActivitiesBloc extends Bloc<ActivitiesEvent, ActivitiesState> {
  /// Dependencies default to real implementations so `ActivitiesBloc()` still
  /// works in production; tests inject fakes.
  ActivitiesBloc({
    ActivityRepository? activities,
    ImportActivityFromGpxUseCase? importGpx,
  }) : _activities = activities ?? ActivityRepository(),
       _importActivityFromGpxUseCase =
           importGpx ?? ImportActivityFromGpxUseCase(),
       super(const ActivitiesState()) {
    on<FetchActivities>(_onFetchActivities);
    on<UpdateActivityName>(_onUpdateActivityName);
    on<DeleteActivity>(_onDeleteActivity);
    on<ImportActivityFromGpx>(_onImportActivityFromGpx);
  }

  final ActivityRepository _activities;
  final ImportActivityFromGpxUseCase _importActivityFromGpxUseCase;

  Future<List<ActivitySummary>> _load() =>
      _activities.fetchSummaries(limit: kActivitiesPageSize);

  Future<void> _onFetchActivities(
    FetchActivities event,
    Emitter<ActivitiesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final activities = await _load();
      // B30: single terminal emit avoids two extra rebuilds and the
      // mid-load flicker between "spinner" → "list" → "spinner" → "list".
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$FetchActivities: $e');
      emit(state.copyWith(error: AppError(e.toString()), isLoading: false));
    }
  }

  Future<void> _onUpdateActivityName(
    UpdateActivityName event,
    Emitter<ActivitiesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _activities.updateName(event.activityId, event.newName);
      final activities = await _load();
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$UpdateActivityName: $e');
      emit(state.copyWith(error: AppError(e.toString()), isLoading: false));
    }
  }

  Future<void> _onDeleteActivity(
    DeleteActivity event,
    Emitter<ActivitiesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _activities.delete(event.activityId);
      final activities = await _load();
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$DeleteActivity: $e');
      emit(state.copyWith(error: AppError(e.toString()), isLoading: false));
    }
  }

  Future<void> _onImportActivityFromGpx(
    ImportActivityFromGpx event,
    Emitter<ActivitiesState> emit,
  ) async {
    // Clear any stale error from a previous failed op so the listener in
    // ActivitiesListPage doesn't re-show it when isLoading toggles back.
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _importActivityFromGpxUseCase(File(event.filePath));
      final activities = await _load();
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$ImportActivityFromGpx: $e');
      final err = e is AppError ? e : AppError(e.toString());
      emit(state.copyWith(error: err, isLoading: false));
    }
  }
}
