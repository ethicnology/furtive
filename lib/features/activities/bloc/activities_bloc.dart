import 'dart:io';

import 'package:bloc_concurrency/bloc_concurrency.dart';
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
    // These handlers all read and replace the same list. A single sequential
    // queue prevents a slow initial fetch from overwriting a newer import, and
    // makes the import status describe the operation that is actually running.
    on<ActivitiesEvent>(_onEvent, transformer: sequential());
  }

  final ActivityRepository _activities;
  final ImportActivityFromGpxUseCase _importActivityFromGpxUseCase;

  Future<List<ActivitySummary>> _load() =>
      _activities.fetchSummaries(limit: kActivitiesPageSize);

  Future<void> _onEvent(
    ActivitiesEvent event,
    Emitter<ActivitiesState> emit,
  ) async {
    switch (event) {
      case FetchActivities():
        await _onFetchActivities(event, emit);
      case FetchMoreActivities():
        await _onFetchMoreActivities(event, emit);
      case ClearActivitiesFeedback():
        emit(
          state.copyWith(error: null, importStatus: ActivityImportStatus.idle),
        );
      case UpdateActivityName():
        await _onUpdateActivityName(event, emit);
      case DeleteActivity():
        await _onDeleteActivity(event, emit);
      case ImportActivityFromGpx():
        await _onImportActivityFromGpx(event, emit);
    }
  }

  Future<void> _onFetchActivities(
    FetchActivities event,
    Emitter<ActivitiesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final activities = await _load();
      // B30: single terminal emit avoids two extra rebuilds and the
      // mid-load flicker between "spinner" → "list" → "spinner" → "list".
      emit(
        state.copyWith(
          activities: activities,
          isLoading: false,
          isLoadingMore: false,
          hasMore: activities.length == kActivitiesPageSize,
        ),
      );
    } catch (e) {
      logs.severe('$FetchActivities: $e');
      emit(state.copyWith(error: AppError(e.toString()), isLoading: false));
    }
  }

  Future<void> _onFetchMoreActivities(
    FetchMoreActivities event,
    Emitter<ActivitiesState> emit,
  ) async {
    final current = state.activities;
    if (current == null ||
        state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    emit(state.copyWith(isLoadingMore: true, error: null));
    try {
      final next = await _activities.fetchSummaries(
        limit: kActivitiesPageSize,
        offset: current.length,
      );
      emit(
        state.copyWith(
          activities: [...current, ...next],
          isLoadingMore: false,
          hasMore: next.length == kActivitiesPageSize,
        ),
      );
    } catch (e) {
      logs.severe('$FetchMoreActivities: $e');
      emit(state.copyWith(error: AppError(e.toString()), isLoadingMore: false));
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
      emit(
        state.copyWith(
          activities: activities,
          isLoading: false,
          hasMore: activities.length == kActivitiesPageSize,
        ),
      );
      event.completion?.complete();
    } catch (e, s) {
      logs.severe('$UpdateActivityName: $e');
      emit(
        state.copyWith(
          error: event.completion == null ? AppError(e.toString()) : null,
          isLoading: false,
        ),
      );
      event.completion?.completeError(e, s);
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
      emit(
        state.copyWith(
          activities: activities,
          isLoading: false,
          hasMore: activities.length == kActivitiesPageSize,
        ),
      );
      event.completion?.complete();
    } catch (e, s) {
      logs.severe('$DeleteActivity: $e');
      emit(
        state.copyWith(
          error: event.completion == null ? AppError(e.toString()) : null,
          isLoading: false,
        ),
      );
      event.completion?.completeError(e, s);
    }
  }

  Future<void> _onImportActivityFromGpx(
    ImportActivityFromGpx event,
    Emitter<ActivitiesState> emit,
  ) async {
    // Clear any stale error from a previous failed op so the listener in
    // ActivitiesListPage doesn't re-show it when isLoading toggles back.
    emit(
      state.copyWith(
        isLoading: true,
        error: null,
        importStatus: ActivityImportStatus.inProgress,
      ),
    );
    try {
      await _importActivityFromGpxUseCase(File(event.filePath));
      final activities = await _load();
      emit(
        state.copyWith(
          activities: activities,
          isLoading: false,
          hasMore: activities.length == kActivitiesPageSize,
          importStatus: ActivityImportStatus.success,
        ),
      );
    } catch (e) {
      logs.severe('$ImportActivityFromGpx: $e');
      final err = e is AppError ? e : AppError(e.toString());
      emit(
        state.copyWith(
          error: err,
          isLoading: false,
          importStatus: ActivityImportStatus.failure,
        ),
      );
    }
  }
}
