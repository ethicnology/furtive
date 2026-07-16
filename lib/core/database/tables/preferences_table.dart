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
  // Opt-out for the once-a-day GitHub release check. Defaults to true; users
  // who want zero network calls can turn it off in Preferences.
  BoolColumn get checkUpdates => boolean().withDefault(const Constant(true))();
  // Opt-out for fetching Protomaps map tiles/style/sprites. Defaults to
  // true (matches today's behaviour for anyone who compiled in a
  // PROTOMAPS_KEY). Every map-tile request reveals the current viewport —
  // and therefore an approximation of the user's live position and, via the
  // activity detail page, past activity locations — to the tile host, tied
  // to its API key and the requester's IP. Turning this off makes the app
  // behave like the keyless FOSS build (a functional, tileless map) even
  // when a key was compiled in. See docs/AUDIT-2026-07.md §5.
  BoolColumn get mapTilesEnabled =>
      boolean().withDefault(const Constant(true))();
  // Whether MainActivity may show on top of the Android lock screen
  // (applied at runtime via LockScreenFacade; the manifest's
  // showWhenLocked="true" is only the cold-start default). Defaults to true
  // (today's behaviour). Off => the live map/position is hidden while the
  // phone is locked. iOS/other platforms ignore this. See
  // docs/AUDIT-2026-07.md §5.
  BoolColumn get showOnLockScreen =>
      boolean().withDefault(const Constant(true))();
}

enum MapThemeColumn { light, dark, white, grayscale, black }

/// Legacy column: map-label language is now derived from the UI locale at
/// fetch time (see `resolveMapLabelLanguage` in `map_remote_data_source`).
/// The enum + column are kept to avoid a SQLite schema change; new rows
/// always write `en` and the value is never read back into UI flows.
enum MapLanguageColumn { en, fr, ru, uk }
