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

class ChangeCheckUpdates extends PreferencesEvent {
  final bool enabled;

  const ChangeCheckUpdates(this.enabled);
}

class ChangeMapTilesEnabled extends PreferencesEvent {
  final bool enabled;

  const ChangeMapTilesEnabled(this.enabled);
}

class ChangeShowOnLockScreen extends PreferencesEvent {
  final bool enabled;

  const ChangeShowOnLockScreen(this.enabled);
}
