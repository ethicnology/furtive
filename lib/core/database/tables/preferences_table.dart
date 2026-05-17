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
}

enum MapThemeColumn { light, dark }

enum MapLanguageColumn { en, fr }
