import 'package:drift/drift.dart';

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
  // App version string the user last saw the changelog for. null on a
  // fresh install (no changelog should pop on day one — only on upgrade).
  // Compared against package_info_plus' Global.app.version, which returns
  // pubspec's version WITHOUT the trailing "+buildNumber" — so changing
  // only the build number won't re-trigger the changelog.
  TextColumn get lastShownChangelogVersion => text().nullable()();
}

enum MapThemeColumn { light, dark, white, grayscale, black }

/// Legacy column: map-label language is now derived from the UI locale at
/// fetch time (see `resolveMapLabelLanguage` in `map_remote_data_source`).
/// The enum + column are kept to avoid a SQLite schema change; new rows
/// always write `en` and the value is never read back into UI flows.
enum MapLanguageColumn { en, fr, ru, uk }
