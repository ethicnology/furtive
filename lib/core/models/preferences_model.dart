import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/preferences_entity.dart';

class PreferencesModel {
  final MapThemeColumn mapTheme;
  final bool hasCompletedOnboarding;
  final String? uiLocale;
  final String? lastShownChangelogVersion;
  final bool mapTilesEnabled;
  final bool showOnLockScreen;
  final bool mapControlsOnLeft;
  final ActivityTypeColumn lastActivityType;
  final RecordingDetailColumn recordingDetail;

  PreferencesModel({
    required this.mapTheme,
    required this.hasCompletedOnboarding,
    this.uiLocale,
    this.lastShownChangelogVersion,
    this.mapTilesEnabled = true,
    this.showOnLockScreen = true,
    this.mapControlsOnLeft = false,
    this.lastActivityType = ActivityTypeColumn.walk,
    this.recordingDetail = RecordingDetailColumn.balanced,
  });

  static PreferencesModel fromEntity(PreferencesEntity preferences) {
    return PreferencesModel(
      mapTheme: MapThemeExtension.fromEntity(preferences.mapTheme),
      hasCompletedOnboarding: preferences.hasCompletedOnboarding,
      uiLocale: preferences.uiLocale,
      lastShownChangelogVersion: preferences.lastShownChangelogVersion,
      mapTilesEnabled: preferences.mapTilesEnabled,
      showOnLockScreen: preferences.showOnLockScreen,
      mapControlsOnLeft: preferences.mapControlsOnLeft,
      lastActivityType: ActivityTypeExtension.fromEntity(
        preferences.lastActivityType,
      ),
      recordingDetail: RecordingDetailExtension.fromEntity(
        preferences.recordingDetail,
      ),
    );
  }

  static PreferencesEntity toEntity(PreferencesModel model) {
    return PreferencesEntity(
      mapTheme: model.mapTheme.toEntity(),
      hasCompletedOnboarding: model.hasCompletedOnboarding,
      uiLocale: model.uiLocale,
      lastShownChangelogVersion: model.lastShownChangelogVersion,
      mapTilesEnabled: model.mapTilesEnabled,
      showOnLockScreen: model.showOnLockScreen,
      mapControlsOnLeft: model.mapControlsOnLeft,
      lastActivityType: model.lastActivityType.toEntity(),
      recordingDetail: model.recordingDetail.toEntity(),
    );
  }
}

/// Storage <-> domain mapping for the activity taxonomy. Written out rather
/// than matched on `name` so adding a value on one side without the other is a
/// compile error, not a runtime surprise on someone's stored data.
extension ActivityTypeExtension on ActivityTypeColumn {
  static ActivityTypeColumn fromEntity(ActivityTypeEntity type) =>
      switch (type) {
        ActivityTypeEntity.walk => ActivityTypeColumn.walk,
        ActivityTypeEntity.run => ActivityTypeColumn.run,
        ActivityTypeEntity.bike => ActivityTypeColumn.bike,
        ActivityTypeEntity.car => ActivityTypeColumn.car,
        ActivityTypeEntity.swim => ActivityTypeColumn.swim,
        ActivityTypeEntity.aircraft => ActivityTypeColumn.aircraft,
        ActivityTypeEntity.other => ActivityTypeColumn.other,
        ActivityTypeEntity.unknown => ActivityTypeColumn.unknown,
      };

  ActivityTypeEntity toEntity() => switch (this) {
    ActivityTypeColumn.walk => ActivityTypeEntity.walk,
    ActivityTypeColumn.run => ActivityTypeEntity.run,
    ActivityTypeColumn.bike => ActivityTypeEntity.bike,
    ActivityTypeColumn.car => ActivityTypeEntity.car,
    ActivityTypeColumn.swim => ActivityTypeEntity.swim,
    ActivityTypeColumn.aircraft => ActivityTypeEntity.aircraft,
    ActivityTypeColumn.other => ActivityTypeEntity.other,
    ActivityTypeColumn.unknown => ActivityTypeEntity.unknown,
  };
}

extension RecordingDetailExtension on RecordingDetailColumn {
  static RecordingDetailColumn fromEntity(RecordingDetailEntity detail) =>
      switch (detail) {
        RecordingDetailEntity.precise => RecordingDetailColumn.precise,
        RecordingDetailEntity.balanced => RecordingDetailColumn.balanced,
        RecordingDetailEntity.endurance => RecordingDetailColumn.endurance,
      };

  RecordingDetailEntity toEntity() => switch (this) {
    RecordingDetailColumn.precise => RecordingDetailEntity.precise,
    RecordingDetailColumn.balanced => RecordingDetailEntity.balanced,
    RecordingDetailColumn.endurance => RecordingDetailEntity.endurance,
  };
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
