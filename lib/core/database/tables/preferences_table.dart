import 'package:drift/drift.dart';

@DataClassName('PreferencesRow')
class Preferences extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mapTheme => textEnum<MapThemeColumn>()();
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
  // Which side of the screen the map's floating controls sit on. Default
  // false = right, today's behaviour. Left-handed users reach across the
  // screen for every control on a phone that is getting wider every
  // generation; the follow/pause/stop buttons are the ones touched mid-run,
  // one-handed, often while moving. The map attribution follows the opposite
  // corner (see MapPage), because the two collided when both sat right.
  BoolColumn get mapControlsOnLeft =>
      boolean().withDefault(const Constant(false))();
  // The activity type to preselect on the record screen. Written on every
  // start so the next recording opens on the last thing the user actually
  // did, which is the only prediction worth making — Strava and OsmAnd both
  // do this rather than asking every time.
  TextColumn get lastActivityType =>
      textEnum<ActivityTypeColumn>().withDefault(const Constant('walk'))();
  // How densely to sample fixes, relative to the activity profile's default.
  // Expressed as an intent rather than a number of seconds: iOS exposes no
  // interval knob at all and Android's is a *requested* rate, so a literal
  // "every N seconds" setting would promise something neither platform
  // guarantees. See RecordingDetailEntity.
  TextColumn get recordingDetail => textEnum<RecordingDetailColumn>()
      .withDefault(const Constant('balanced'))();
}

enum MapThemeColumn { light, dark, white, grayscale, black }

/// Storage spelling of ActivityTypeEntity. Duplicated rather than reusing the
/// entity so a rename in the domain layer cannot silently rewrite what is
/// already on disk — same reason ActivityPointsStatusColumn exists.
/// Adding a value here needs no migration — drift stores the name in a plain
/// TEXT column with no CHECK constraint. **Removing** one does: any stored row
/// still holding it stops mapping back to an enum and fails on read, so a
/// removal must be paired with a migration rewriting those rows (see the v14
/// step in local_database.dart).
enum ActivityTypeColumn { walk, run, bike, car, swim, aircraft, other, unknown }

enum RecordingDetailColumn { precise, balanced, endurance }
