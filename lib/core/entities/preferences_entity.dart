import 'package:dart_mappable/dart_mappable.dart';

part 'preferences_entity.mapper.dart';

enum MapThemeEntity { light, dark, white, grayscale, black }

enum MapLanguageEntity { en, fr, ru, uk }

@MappableClass()
class PreferencesEntity with PreferencesEntityMappable {
  final MapThemeEntity mapTheme;
  // Legacy DB column. Map labels are now derived from the UI locale at
  // fetch time (see resolveMapLabelLanguage). Kept for backward compat
  // with v1.1 rows; new writes always default to `en`.
  final MapLanguageEntity mapLanguage;
  // Legacy DB column. The GPS distanceFilter is now hardcoded to 0
  // (every fix) in LocationGpsDataSource. Kept for backward compat;
  // new writes always default to 0.
  final int accuracyInMeters;
  final bool hasCompletedOnboarding;
  // null = follow device locale; BCP-47 code overrides the system locale.
  final String? uiLocale;
  // Last app version the user dismissed the changelog for. null = fresh
  // install (the onboarding wizard stamps the current version on finish);
  // the schema-v2 migration back-fills upgrading users with the '0.0.0'
  // sentinel so the post-upgrade changelog shows once.
  final String? lastShownChangelogVersion;
  // Whether the daily GitHub release check may run. Defaults to true.
  final bool checkUpdates;
  // Whether map tiles/style/sprites may be fetched from Protomaps. Defaults
  // to true (today's behaviour). Off => the app renders the same tileless
  // map as the keyless FOSS build, with zero tile requests, even if a
  // PROTOMAPS_KEY was compiled in — see preferences_table.dart.
  final bool mapTilesEnabled;
  // Whether the app may show on top of the Android lock screen. Defaults
  // to true (today's behaviour). See preferences_table.dart.
  final bool showOnLockScreen;

  PreferencesEntity({
    required this.mapTheme,
    this.mapLanguage = MapLanguageEntity.en,
    this.accuracyInMeters = 0,
    // Required (no default) so callers can't silently reset it to false.
    // Caused a regression: PreferencesPage rebuilt the entity by hand and
    // omitted this field, writing false back to DB → wizard reappeared.
    required this.hasCompletedOnboarding,
    this.uiLocale,
    this.lastShownChangelogVersion,
    this.checkUpdates = true,
    this.mapTilesEnabled = true,
    this.showOnLockScreen = true,
  });
}
