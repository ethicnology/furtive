import 'package:furtive/core/entities/activity_profile.dart';
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

class ChangeMapTilesEnabled extends PreferencesEvent {
  final bool enabled;

  const ChangeMapTilesEnabled(this.enabled);
}

class ChangeShowOnLockScreen extends PreferencesEvent {
  final bool enabled;

  const ChangeShowOnLockScreen(this.enabled);
}

class ChangeMapControlsOnLeft extends PreferencesEvent {
  final bool onLeft;

  const ChangeMapControlsOnLeft(this.onLeft);
}

class ChangeRecordingDetail extends PreferencesEvent {
  final RecordingDetailEntity detail;

  const ChangeRecordingDetail(this.detail);
}
