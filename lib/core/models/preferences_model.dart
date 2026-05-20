import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/entities/preferences_entity.dart';

class PreferencesModel {
  final MapThemeColumn mapTheme;
  final MapLanguageColumn mapLanguage;
  final int accuracyInMeters;
  final bool hasCompletedOnboarding;
  final String? uiLocale;

  PreferencesModel({
    required this.mapTheme,
    required this.mapLanguage,
    required this.accuracyInMeters,
    required this.hasCompletedOnboarding,
    this.uiLocale,
  });

  static PreferencesModel fromEntity(PreferencesEntity preferences) {
    return PreferencesModel(
      mapTheme: MapThemeExtension.fromEntity(preferences.mapTheme),
      mapLanguage: MapLanguageExtension.fromEntity(preferences.mapLanguage),
      accuracyInMeters: preferences.accuracyInMeters,
      hasCompletedOnboarding: preferences.hasCompletedOnboarding,
      uiLocale: preferences.uiLocale,
    );
  }

  static PreferencesEntity toEntity(PreferencesModel model) {
    return PreferencesEntity(
      mapTheme: model.mapTheme.toEntity(),
      mapLanguage: model.mapLanguage.toEntity(),
      accuracyInMeters: model.accuracyInMeters,
      hasCompletedOnboarding: model.hasCompletedOnboarding,
      uiLocale: model.uiLocale,
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
    }
  }

  MapThemeEntity toEntity() {
    switch (this) {
      case MapThemeColumn.light:
        return MapThemeEntity.light;
      case MapThemeColumn.dark:
        return MapThemeEntity.dark;
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
