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
  // Last app version the user has dismissed the changelog for. null marker
  // means "not initialised yet" — main.dart back-fills it on startup.
  final String? lastShownChangelogVersion;

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
  });
}
