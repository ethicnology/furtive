import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/entities/activity_profile.dart';

part 'preferences_entity.mapper.dart';

enum MapThemeEntity { light, dark, white, grayscale, black }

@MappableClass()
class PreferencesEntity with PreferencesEntityMappable {
  final MapThemeEntity mapTheme;
  final bool hasCompletedOnboarding;
  // null = follow device locale; BCP-47 code overrides the system locale.
  final String? uiLocale;
  // Last app version the user dismissed the changelog for. null = fresh
  // install (the onboarding wizard stamps the current version on finish);
  // the schema-v2 migration back-fills upgrading users with the '0.0.0'
  // sentinel so the post-upgrade changelog shows once.
  final String? lastShownChangelogVersion;
  // Whether map tiles/style/sprites may be fetched from Protomaps. Defaults
  // to true (today's behaviour). Off => the app renders the same tileless
  // map as the keyless FOSS build, with zero tile requests, even if a
  // PROTOMAPS_KEY was compiled in — see preferences_table.dart.
  final bool mapTilesEnabled;
  // Whether the app may show on top of the Android lock screen. Defaults
  // to true (today's behaviour). See preferences_table.dart.
  final bool showOnLockScreen;
  // false = floating map controls on the right (default). See
  // preferences_table.dart.
  final bool mapControlsOnLeft;
  // Activity type preselected on the record screen — the last one recorded.
  final ActivityTypeEntity lastActivityType;
  // Sampling density relative to the activity profile's own default.
  final RecordingDetailEntity recordingDetail;

  PreferencesEntity({
    required this.mapTheme,
    // Required (no default) so callers can't silently reset it to false.
    // Caused a regression: PreferencesPage rebuilt the entity by hand and
    // omitted this field, writing false back to DB → wizard reappeared.
    required this.hasCompletedOnboarding,
    this.uiLocale,
    this.lastShownChangelogVersion,
    this.mapTilesEnabled = true,
    this.showOnLockScreen = true,
    this.mapControlsOnLeft = false,
    this.lastActivityType = ActivityTypeEntity.walk,
    this.recordingDetail = RecordingDetailEntity.balanced,
  });
}
