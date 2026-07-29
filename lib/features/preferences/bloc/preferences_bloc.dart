import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/facades/lock_screen_facade.dart';
import 'package:furtive/core/locale_cubit.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_state.dart';

class PreferencesBloc extends Bloc<PreferencesEvent, PreferencesState> {
  PreferencesBloc._({
    required PreferencesState initialState,
    PreferencesRepository? preferences,
    LockScreenFacade? lockScreen,
  }) : _preferences = preferences ?? PreferencesRepository(),
       _lockScreenFacade = lockScreen ?? LockScreenFacade(),
       super(initialState) {
    on<LoadPreferences>(_onLoadPreferences);
    on<UpdatePreferences>(_onUpdatePreferences);
    on<ChangeMapTheme>(_onChangeMapTheme);
    on<ChangeUiLocale>(_onChangeUiLocale);
    on<ChangeMapTilesEnabled>(_onChangeMapTilesEnabled);
    on<ChangeShowOnLockScreen>(_onChangeShowOnLockScreen);
    on<ChangeMapControlsOnLeft>(_onChangeMapControlsOnLeft);
    on<ChangeRecordingDetail>(_onChangeRecordingDetail);
  }

  final PreferencesRepository _preferences;
  final LockScreenFacade _lockScreenFacade;

  /// Async factory: the initial state needs a storage read, which a constructor
  /// cannot await. [repository]/[lockScreen] are injectable for tests.
  static Future<PreferencesBloc> create({
    PreferencesRepository? repository,
    LockScreenFacade? lockScreen,
  }) async {
    final repo = repository ?? PreferencesRepository();
    final preferences = await repo.fetch();
    return PreferencesBloc._(
      initialState: PreferencesState(
        preferences: preferences,
        persisted: preferences,
      ),
      preferences: repo,
      lockScreen: lockScreen,
    );
  }

  Future<void> _onLoadPreferences(
    LoadPreferences event,
    Emitter<PreferencesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final preferences = await _preferences.fetch();
      emit(
        state.copyWith(
          preferences: preferences,
          persisted: preferences,
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: AppError(e.toString()), isLoading: false));
    }
  }

  void _onChangeMapTheme(ChangeMapTheme event, Emitter<PreferencesState> emit) {
    final newPreferences = state.preferences.copyWith(mapTheme: event.theme);
    emit(state.copyWith(preferences: newPreferences));
  }

  void _onChangeUiLocale(ChangeUiLocale event, Emitter<PreferencesState> emit) {
    final newPreferences = state.preferences.copyWith(
      uiLocale: event.languageCode,
    );
    emit(state.copyWith(preferences: newPreferences));
  }

  void _onChangeMapTilesEnabled(
    ChangeMapTilesEnabled event,
    Emitter<PreferencesState> emit,
  ) {
    final newPreferences = state.preferences.copyWith(
      mapTilesEnabled: event.enabled,
    );
    emit(state.copyWith(preferences: newPreferences));
  }

  void _onChangeShowOnLockScreen(
    ChangeShowOnLockScreen event,
    Emitter<PreferencesState> emit,
  ) {
    final newPreferences = state.preferences.copyWith(
      showOnLockScreen: event.enabled,
    );
    emit(state.copyWith(preferences: newPreferences));
  }

  void _onChangeMapControlsOnLeft(
    ChangeMapControlsOnLeft event,
    Emitter<PreferencesState> emit,
  ) {
    emit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          mapControlsOnLeft: event.onLeft,
        ),
      ),
    );
  }

  void _onChangeRecordingDetail(
    ChangeRecordingDetail event,
    Emitter<PreferencesState> emit,
  ) {
    emit(
      state.copyWith(
        preferences: state.preferences.copyWith(recordingDetail: event.detail),
      ),
    );
  }

  Future<void> _onUpdatePreferences(
    UpdatePreferences event,
    Emitter<PreferencesState> emit,
  ) async {
    // Diff against the last-persisted preferences, NOT state.preferences: the
    // Change* handlers already mutate state.preferences live as the user
    // edits the form, so comparing against it here always finds "no change"
    // and every live side effect below (map re-init, lock-screen toggle)
    // would silently no-op until the next app restart. See
    // docs/REVIEW-2026-07-FULL-APP.md C1.
    final previous = state.persisted;
    emit(state.copyWith(isSaving: true, error: null, saveCompleted: null));
    try {
      await _preferences.store(event.preferences);
    } catch (e, s) {
      // The page now STAYS MOUNTED until saveCompleted flips (it no longer pops
      // in the same frame as dispatching Apply), so a failed write is actually
      // reportable instead of being logged into the void while the user believes
      // their settings were stored.
      logs.severe('$UpdatePreferences', error: e, trace: s);
      emit(
        state.copyWith(
          isSaving: false,
          saveCompleted: false,
          error: e is AppError ? e : AppError(e.toString()),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        preferences: event.preferences,
        persisted: event.preferences,
        isSaving: false,
        saveCompleted: true,
      ),
    );

    // Re-init the map only when something the map style actually depends on
    // changed. Re-firing InitMap for an unrelated toggle (the lock-screen one)
    // needlessly re-resolves the style and flashes the loading UI. The position
    // stream is preserved either way (InitMap is idempotent on it), so a live
    // recording is never disturbed.
    final mapChanged =
        previous.mapTheme != event.preferences.mapTheme ||
        previous.mapTilesEnabled != event.preferences.mapTilesEnabled;
    if (mapChanged) getIt<MapBloc>().add(InitMap());

    // The recording preferences reach the map by a lighter path: they move
    // buttons and change the sampling rate, neither of which needs the style
    // re-resolved. Without this the map keeps whatever it read at startup, so
    // flipping the control side appeared to do nothing until an app restart.
    final recordingChanged =
        previous.mapControlsOnLeft != event.preferences.mapControlsOnLeft ||
        previous.recordingDetail != event.preferences.recordingDetail;
    if (recordingChanged) {
      getIt<MapBloc>().add(const RefreshRecordingPreferences());
    }

    // Apply the locale override immediately so the UI reflects the change
    // without requiring an app restart.
    final code = event.preferences.uiLocale;
    getIt<LocaleCubit>().setLocale(code);

    // Apply the lock-screen visibility toggle immediately (Android only,
    // no-op elsewhere) so the user doesn't need to restart the app to see
    // the effect.
    if (previous.showOnLockScreen != event.preferences.showOnLockScreen) {
      await _lockScreenFacade.setShowWhenLocked(
        event.preferences.showOnLockScreen,
      );
    }
  }
}
