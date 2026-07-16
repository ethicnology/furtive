import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/facades/lock_screen_facade.dart';
import 'package:furtive/core/locale_cubit.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/usecases/get_preferences_use_case.dart';
import 'package:furtive/core/usecases/update_preferences_use_case.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_state.dart';

class PreferencesBloc extends Bloc<PreferencesEvent, PreferencesState> {
  final _getPreferencesUseCase = GetPreferencesUseCase();
  final _updatePreferencesUseCase = UpdatePreferencesUseCase();
  final _lockScreenFacade = LockScreenFacade();

  PreferencesBloc._({required PreferencesState initialState})
    : super(initialState) {
    on<LoadPreferences>(_onLoadPreferences);
    on<UpdatePreferences>(_onUpdatePreferences);
    on<ChangeMapTheme>(_onChangeMapTheme);
    on<ChangeUiLocale>(_onChangeUiLocale);
    on<ChangeCheckUpdates>(_onChangeCheckUpdates);
    on<ChangeMapTilesEnabled>(_onChangeMapTilesEnabled);
    on<ChangeShowOnLockScreen>(_onChangeShowOnLockScreen);
  }

  static Future<PreferencesBloc> create() async {
    final getPreferencesUseCase = GetPreferencesUseCase();
    final preferences = await getPreferencesUseCase();
    final initialState = PreferencesState(
      preferences: preferences,
      persisted: preferences,
    );
    return PreferencesBloc._(initialState: initialState);
  }

  Future<void> _onLoadPreferences(
    LoadPreferences event,
    Emitter<PreferencesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final preferences = await _getPreferencesUseCase();
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

  void _onChangeCheckUpdates(
    ChangeCheckUpdates event,
    Emitter<PreferencesState> emit,
  ) {
    final newPreferences = state.preferences.copyWith(
      checkUpdates: event.enabled,
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
    try {
      await _updatePreferencesUseCase(event.preferences);
    } catch (e, s) {
      // PreferencesPage pops immediately after dispatching Apply, so by the
      // time this settles there is very likely no UI left to show an error
      // on. Logging at least makes a failed save discoverable in the
      // exported logs instead of vanishing into the bloc's global error
      // handler silently. See M5 in docs/REVIEW-2026-07-FULL-APP.md.
      logs.severe('$UpdatePreferences', error: e, trace: s);
      return;
    }

    // The page pops (and closes this bloc) right after dispatching Apply; the
    // DB write above can outlive it. emit() would throw on a closed bloc, so
    // it alone is guarded — but the side effects below (locale, map re-init,
    // lock-screen) don't touch bloc state at all and must run regardless of
    // isClosed. Previously the single `if (isClosed) return;` above skipped
    // them too whenever the write outlived the pop, leaving settings
    // persisted to disk but never actually applied until the next app
    // restart. See M5 in docs/REVIEW-2026-07-FULL-APP.md.
    if (!isClosed) {
      emit(
        state.copyWith(
          preferences: event.preferences,
          persisted: event.preferences,
        ),
      );
    }

    // Re-init the map only when something the map style actually depends on
    // changed. Re-firing InitMap for an unrelated toggle (e.g. "check for
    // updates") needlessly re-localises, reloads the map config and flashes
    // the loading UI. The position stream is preserved either way (InitMap is
    // idempotent on it), so a live recording is never disturbed.
    final mapChanged =
        previous.mapTheme != event.preferences.mapTheme ||
        previous.mapLanguage != event.preferences.mapLanguage ||
        previous.mapTilesEnabled != event.preferences.mapTilesEnabled;
    if (mapChanged) getIt<MapBloc>().add(InitMap());

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
