import 'package:furtive/core/entities/preferences_entity.dart';

sealed class PreferencesEvent {
  const PreferencesEvent();
}

class LoadPreferences extends PreferencesEvent {
  const LoadPreferences();
}

class UpdatePreferences extends PreferencesEvent {
  final PreferencesEntity preferences;

  const UpdatePreferences(this.preferences);
}

class ChangeMapTheme extends PreferencesEvent {
  final MapThemeEntity theme;

  const ChangeMapTheme(this.theme);
}

class ChangeUiLocale extends PreferencesEvent {
  // null = follow device locale
  final String? languageCode;

  const ChangeUiLocale(this.languageCode);
}
