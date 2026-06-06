import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/entities/preferences_entity.dart';

class PreferencesModel {
  final MapThemeColumn mapTheme;
  final MapLanguageColumn mapLanguage;
  final int accuracyInMeters;
  final bool hasCompletedOnboarding;
  final String? uiLocale;
  final String? lastShownChangelogVersion;
  final bool checkUpdates;

  PreferencesModel({
    required this.mapTheme,
    required this.mapLanguage,
    required this.accuracyInMeters,
    required this.hasCompletedOnboarding,
    this.uiLocale,
    this.lastShownChangelogVersion,
    this.checkUpdates = true,
  });

  static PreferencesModel fromEntity(PreferencesEntity preferences) {
    return PreferencesModel(
      mapTheme: MapThemeExtension.fromEntity(preferences.mapTheme),
      mapLanguage: MapLanguageExtension.fromEntity(preferences.mapLanguage),
      accuracyInMeters: preferences.accuracyInMeters,
      hasCompletedOnboarding: preferences.hasCompletedOnboarding,
      uiLocale: preferences.uiLocale,
      lastShownChangelogVersion: preferences.lastShownChangelogVersion,
      checkUpdates: preferences.checkUpdates,
    );
  }

  static PreferencesEntity toEntity(PreferencesModel model) {
    return PreferencesEntity(
      mapTheme: model.mapTheme.toEntity(),
      mapLanguage: model.mapLanguage.toEntity(),
      accuracyInMeters: model.accuracyInMeters,
      hasCompletedOnboarding: model.hasCompletedOnboarding,
      uiLocale: model.uiLocale,
      lastShownChangelogVersion: model.lastShownChangelogVersion,
      checkUpdates: model.checkUpdates,
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

extension MapLanguageExtension on MapLanguageColumn {
  static MapLanguageColumn fromEntity(MapLanguageEntity language) {
    switch (language) {
      case MapLanguageEntity.en:
        return MapLanguageColumn.en;
      case MapLanguageEntity.fr:
        return MapLanguageColumn.fr;
      case MapLanguageEntity.ru:
        return MapLanguageColumn.ru;
      case MapLanguageEntity.uk:
        return MapLanguageColumn.uk;
    }
  }

  MapLanguageEntity toEntity() {
    switch (this) {
      case MapLanguageColumn.en:
        return MapLanguageEntity.en;
      case MapLanguageColumn.fr:
        return MapLanguageEntity.fr;
      case MapLanguageColumn.ru:
        return MapLanguageEntity.ru;
      case MapLanguageColumn.uk:
        return MapLanguageEntity.uk;
    }
  }
}
