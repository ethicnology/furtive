import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/locale_cubit.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/usecases/get_preferences_use_case.dart';
import 'package:furtive/core/usecases/update_preferences_use_case.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_event.dart';
import 'package:furtive/features/preferences/bloc/preferences_state.dart';

class PreferencesBloc extends Bloc<PreferencesEvent, PreferencesState> {
  final _getPreferencesUseCase = GetPreferencesUseCase();
  final _updatePreferencesUseCase = UpdatePreferencesUseCase();

  PreferencesBloc._({required PreferencesState initialState})
    : super(initialState) {
    on<LoadPreferences>(_onLoadPreferences);
    on<UpdatePreferences>(_onUpdatePreferences);
    on<ChangeMapTheme>(_onChangeMapTheme);
    on<ChangeMapLanguage>(_onChangeMapLanguage);
    on<ChangeAccuracy>(_onChangeAccuracy);
    on<ChangeUiLocale>(_onChangeUiLocale);
  }

  static Future<PreferencesBloc> create() async {
    final getPreferencesUseCase = GetPreferencesUseCase();
    final preferences = await getPreferencesUseCase();
    final initialState = PreferencesState(preferences: preferences);
    return PreferencesBloc._(initialState: initialState);
  }

  Future<void> _onLoadPreferences(
    LoadPreferences event,
    Emitter<PreferencesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final preferences = await _getPreferencesUseCase();
      emit(state.copyWith(preferences: preferences, isLoading: false));
    } catch (e) {
      emit(state.copyWith(error: AppError(e.toString()), isLoading: false));
    }
  }

  void _onChangeMapTheme(ChangeMapTheme event, Emitter<PreferencesState> emit) {
    final newPreferences = state.preferences.copyWith(mapTheme: event.theme);
    emit(state.copyWith(preferences: newPreferences));
  }

  void _onChangeMapLanguage(
    ChangeMapLanguage event,
    Emitter<PreferencesState> emit,
  ) {
    final newPreferences = state.preferences.copyWith(
      mapLanguage: event.language,
    );
    emit(state.copyWith(preferences: newPreferences));
  }

  void _onChangeAccuracy(ChangeAccuracy event, Emitter<PreferencesState> emit) {
    final newPreferences = state.preferences.copyWith(
      accuracyInMeters: event.accuracyInMeters,
    );
    emit(state.copyWith(preferences: newPreferences));
  }

  void _onChangeUiLocale(
    ChangeUiLocale event,
    Emitter<PreferencesState> emit,
  ) {
    final newPreferences = state.preferences.copyWith(
      uiLocale: event.languageCode,
    );
    emit(state.copyWith(preferences: newPreferences));
  }

  Future<void> _onUpdatePreferences(
    UpdatePreferences event,
    Emitter<PreferencesState> emit,
  ) async {
    await _updatePreferencesUseCase(event.preferences);
    emit(state.copyWith(preferences: event.preferences));
    getIt<MapBloc>().add(InitMap());
    // Apply the locale override immediately so the UI reflects the change
    // without requiring an app restart.
    final code = event.preferences.uiLocale;
    getIt<LocaleCubit>().setLocale(code);
  }
}
