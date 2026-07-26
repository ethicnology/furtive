import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/entities/preferences_entity.dart';

class PreferencesModel {
  final MapThemeColumn mapTheme;
  final int accuracyInMeters;
  final bool hasCompletedOnboarding;
  final String? uiLocale;
  final String? lastShownChangelogVersion;
  final bool checkUpdates;
  final bool mapTilesEnabled;
  final bool showOnLockScreen;

  PreferencesModel({
    required this.mapTheme,
    required this.accuracyInMeters,
    required this.hasCompletedOnboarding,
    this.uiLocale,
    this.lastShownChangelogVersion,
    this.checkUpdates = true,
    this.mapTilesEnabled = true,
    this.showOnLockScreen = true,
  });

  static PreferencesModel fromEntity(PreferencesEntity preferences) {
    return PreferencesModel(
      mapTheme: MapThemeExtension.fromEntity(preferences.mapTheme),
      accuracyInMeters: preferences.accuracyInMeters,
      hasCompletedOnboarding: preferences.hasCompletedOnboarding,
      uiLocale: preferences.uiLocale,
      lastShownChangelogVersion: preferences.lastShownChangelogVersion,
      checkUpdates: preferences.checkUpdates,
      mapTilesEnabled: preferences.mapTilesEnabled,
      showOnLockScreen: preferences.showOnLockScreen,
    );
  }

  static PreferencesEntity toEntity(PreferencesModel model) {
    return PreferencesEntity(
      mapTheme: model.mapTheme.toEntity(),
      accuracyInMeters: model.accuracyInMeters,
      hasCompletedOnboarding: model.hasCompletedOnboarding,
      uiLocale: model.uiLocale,
      lastShownChangelogVersion: model.lastShownChangelogVersion,
      checkUpdates: model.checkUpdates,
      mapTilesEnabled: model.mapTilesEnabled,
      showOnLockScreen: model.showOnLockScreen,
    );
  }
}

extension MapThemeExtension on MapThemeColumn {
  static MapThemeColumn fromEntity(MapThemeEntity theme) {
    switch (theme) {
      case MapThemeEntity.light:
        return MapThemeColumn.light;
      case MapThemeEntity.dark:
        return MapThemeColumn.dark;
      case MapThemeEntity.white:
        return MapThemeColumn.white;
      case MapThemeEntity.grayscale:
        return MapThemeColumn.grayscale;
      case MapThemeEntity.black:
        return MapThemeColumn.black;
    }
  }

  MapThemeEntity toEntity() {
    switch (this) {
      case MapThemeColumn.light:
        return MapThemeEntity.light;
      case MapThemeColumn.dark:
        return MapThemeEntity.dark;
      case MapThemeColumn.white:
        return MapThemeEntity.white;
      case MapThemeColumn.grayscale:
        return MapThemeEntity.grayscale;
      case MapThemeColumn.black:
        return MapThemeEntity.black;
    }
  }
}
