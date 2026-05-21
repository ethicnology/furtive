import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/usecases/get_activities_use_case.dart';
import 'package:furtive/core/usecases/import_activity_from_gpx_use_case.dart';
import 'package:furtive/core/usecases/update_activity_name_use_case.dart';
import 'package:furtive/core/usecases/delete_activity_use_case.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:furtive/features/activities/bloc/activities_state.dart';

class ActivitiesBloc extends Bloc<ActivitiesEvent, ActivitiesState> {
  final _getActivitiesUseCase = GetActivitiesUseCase();
  final _updateActivityNameUseCase = UpdateActivityNameUseCase();
  final _deleteActivityUseCase = DeleteActivityUseCase();
  final _importActivityFromGpxUseCase = ImportActivityFromGpxUseCase();

  ActivitiesBloc() : super(const ActivitiesState()) {
    on<FetchActivities>(_onFetchActivities);
    on<SelectActivity>(_onSelectActivity);
    on<UpdateActivityName>(_onUpdateActivityName);
    on<DeleteActivity>(_onDeleteActivity);
    on<ImportActivityFromGpx>(_onImportActivityFromGpx);
  }

  Future<void> _onFetchActivities(
    FetchActivities event,
    Emitter<ActivitiesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final activities = await _getActivitiesUseCase();
      // B30: single terminal emit avoids two extra rebuilds and the
      // mid-load flicker between "spinner" → "list" → "spinner" → "list".
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$FetchActivities: $e');
      emit(
        state.copyWith(error: AppError(e.toString()), isLoading: false),
      );
    }
  }

  void _onSelectActivity(SelectActivity event, Emitter<ActivitiesState> emit) {
    emit(state.copyWith(selectedActivity: event.activity));
  }

  Future<void> _onUpdateActivityName(
    UpdateActivityName event,
    Emitter<ActivitiesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _updateActivityNameUseCase(event.activityId, event.newName);
      final activities = await _getActivitiesUseCase();
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$UpdateActivityName: $e');
      emit(
        state.copyWith(error: AppError(e.toString()), isLoading: false),
      );
    }
  }

  Future<void> _onDeleteActivity(
    DeleteActivity event,
    Emitter<ActivitiesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _deleteActivityUseCase(event.activityId);
      final activities = await _getActivitiesUseCase();
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$DeleteActivity: $e');
      emit(
        state.copyWith(error: AppError(e.toString()), isLoading: false),
      );
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
      final activities = await _getActivitiesUseCase();
      emit(state.copyWith(activities: activities, isLoading: false));
    } catch (e) {
      logs.severe('$ImportActivityFromGpx: $e');
      final err = e is AppError ? e : AppError(e.toString());
      emit(state.copyWith(error: err, isLoading: false));
    }
  }
}
