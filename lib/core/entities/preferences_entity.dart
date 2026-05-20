import 'package:dart_mappable/dart_mappable.dart';

part 'preferences_entity.mapper.dart';

enum MapThemeEntity { light, dark }

enum MapLanguageEntity { en, fr, ru, uk }

@MappableClass()
class PreferencesEntity with PreferencesEntityMappable {
  final MapThemeEntity mapTheme;
  final MapLanguageEntity mapLanguage;
  final int accuracyInMeters;
  final bool hasCompletedOnboarding;
  // null = follow device locale; BCP-47 code overrides the system locale.
  final String? uiLocale;

  PreferencesEntity({
    required this.mapTheme,
    required this.mapLanguage,
    required this.accuracyInMeters,
    this.hasCompletedOnboarding = false,
    this.uiLocale,
  });
}
