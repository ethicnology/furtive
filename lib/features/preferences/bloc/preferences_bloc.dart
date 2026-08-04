import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/preferences_entity.dart';
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
    // Writes are serialised: every Change* handler auto-dispatches one, and
    // concurrent processing could persist a stale snapshot over a newer one
    // (two rapid toggles, second write landing first). sequential() queues
    // them in dispatch order, so the last toggle always wins.
    on<UpdatePreferences>(_onUpdatePreferences, transformer: sequential());
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

  /// Applies an edit optimistically, then persists it: there is no Apply
  /// button — every change takes effect (and is stored) immediately. The
  /// write itself runs in _onUpdatePreferences, serialised with every other
  /// pending write; a failure rolls the control back to the persisted value
  /// and surfaces a snackbar.
  void _applyChange(
    PreferencesEntity Function(PreferencesEntity) update,
    Emitter<PreferencesState> emit,
  ) {
    final newPreferences = update(state.preferences);
    emit(state.copyWith(preferences: newPreferences));
    add(UpdatePreferences(newPreferences));
  }

  void _onChangeMapTheme(
    ChangeMapTheme event,
    Emitter<PreferencesState> emit,
  ) => _applyChange((p) => p.copyWith(mapTheme: event.theme), emit);

  void _onChangeUiLocale(
    ChangeUiLocale event,
    Emitter<PreferencesState> emit,
  ) => _applyChange((p) => p.copyWith(uiLocale: event.languageCode), emit);

  void _onChangeMapTilesEnabled(
    ChangeMapTilesEnabled event,
    Emitter<PreferencesState> emit,
  ) => _applyChange((p) => p.copyWith(mapTilesEnabled: event.enabled), emit);

  void _onChangeShowOnLockScreen(
    ChangeShowOnLockScreen event,
    Emitter<PreferencesState> emit,
  ) => _applyChange((p) => p.copyWith(showOnLockScreen: event.enabled), emit);

  void _onChangeMapControlsOnLeft(
    ChangeMapControlsOnLeft event,
    Emitter<PreferencesState> emit,
  ) => _applyChange((p) => p.copyWith(mapControlsOnLeft: event.onLeft), emit);

  void _onChangeRecordingDetail(
    ChangeRecordingDetail event,
    Emitter<PreferencesState> emit,
  ) => _applyChange((p) => p.copyWith(recordingDetail: event.detail), emit);

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
      logs.severe('$UpdatePreferences', error: e, trace: s);
      emit(
        state.copyWith(
          // Roll the control back to the last-persisted value so the UI never
          // shows a setting that isn't actually stored — unless a newer edit
          // is already queued behind this write, in which case its own write
          // settles the final value and rolling back would clobber it.
          preferences: state.preferences == event.preferences
              ? state.persisted
              : state.preferences,
          isSaving: false,
          saveCompleted: false,
          error: e is AppError ? e : AppError(e.toString()),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        // Do NOT write preferences: event.preferences here — a newer Change*
        // may already have moved state.preferences past this write while it
        // was queued, and stamping the older snapshot back would flicker the
        // control. state.preferences is always >= this write's snapshot.
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
