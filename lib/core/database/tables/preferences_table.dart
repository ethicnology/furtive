import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show Locale;

@DataClassName('PreferencesRow')
class Preferences extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mapTheme => textEnum<MapThemeColumn>()();
  TextColumn get mapLanguage => textEnum<MapLanguageColumn>()();
  IntColumn get accuracyInMeters => integer()();
  // false on a freshly created DB (-> wizard shows); true after migration
  // for existing users (-> wizard does not show).
  BoolColumn get hasCompletedOnboarding =>
      boolean().withDefault(const Constant(false))();
  // null = follow device locale; non-null = BCP-47 language code override.
  TextColumn get uiLocale => text().nullable()();
}

enum MapThemeColumn { light, dark }

/// Subset of the 41 BCP-47 codes accepted by the Protomaps v5 style endpoint
/// (docs.protomaps.com/basemaps/localization). Limited to the languages the
/// app's UI itself supports — extending the picker beyond the UI languages
/// has no value since the user wouldn't be able to read the surrounding
/// chrome anyway.
enum MapLanguageColumn {
  en,
  fr,
  ru,
  uk;

  /// Pick the best Protomaps label language for a Flutter [locale]. Falls
  /// back to English when [locale]'s language code isn't one of ours.
  static MapLanguageColumn fromLocale(Locale locale) {
    for (final candidate in values) {
      if (candidate.name == locale.languageCode) return candidate;
    }
    return MapLanguageColumn.en;
  }
}
