import 'package:dart_mappable/dart_mappable.dart';

part 'preferences_entity.mapper.dart';

enum MapThemeEntity { light, dark, white, grayscale, black }

enum MapLanguageEntity { en, fr, ru, uk }

@MappableClass()
class PreferencesEntity with PreferencesEntityMappable {
  final MapThemeEntity mapTheme;
  final MapLanguageEntity mapLanguage;
  final int accuracyInMeters;
  final bool hasCompletedOnboarding;
  // null = follow device locale; BCP-47 code overrides the system locale.
  final String? uiLocale;
  // Last app version the user has dismissed the changelog for. null marker
  // means "not initialised yet" — main.dart back-fills it on startup.
  final String? lastShownChangelogVersion;

  PreferencesEntity({
    required this.mapTheme,
    required this.mapLanguage,
    required this.accuracyInMeters,
    // Required (no default) so callers can't silently reset it to false.
    // Caused a regression: PreferencesPage rebuilt the entity by hand and
    // omitted this field, writing false back to DB → wizard reappeared.
    required this.hasCompletedOnboarding,
    this.uiLocale,
    this.lastShownChangelogVersion,
  });
}
