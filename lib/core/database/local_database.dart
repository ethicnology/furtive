import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:furtive/core/database/tables/activities_table.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

@DriftDatabase(tables: [Activities, ActivityPoints, Preferences])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase() : super(_openConnection());

  /// Inject a query executor (e.g. `NativeDatabase.memory()`) for tests.
  LocalDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async => await m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      // Guard against a sideloaded older build opening a newer DB (plausible
      // for a GitHub-releases/F-Droid audience rolling back a bad release).
      // Without this, drift still calls onUpgrade(from: 8, to: <8); every
      // `if (from < N)` block below no-ops, and drift then stamps the LOWER
      // version into user_version while the schema itself stays at the
      // higher version. The next real upgrade re-runs every step against a
      // schema that already has the columns/indices, and `ADD COLUMN` /
      // `CREATE INDEX` (no IF-guard) throw — bricking the database until the
      // user clears app data. Refuse outright instead.
      if (from > to) {
        throw StateError(
          'Refusing to downgrade database schema from v$from to v$to. '
          'Reinstall the version that created this database, or clear app '
          'data to start fresh.',
        );
      }
      // Schema migrations live here. Each `if (from < N)` block runs in order
      // for users coming from an earlier version.
      //
      // Wrapped in a transaction: SQLite DDL is transactional, and without
      // this a process kill mid-upgrade (OOM, swipe-kill, battery pull) can
      // leave some statements applied while user_version (only bumped after
      // every step succeeds) still reads the old version. On the next launch
      // drift replays the whole block from the same `from`, and the
      // already-applied `ADD COLUMN` / `CREATE INDEX` statements throw
      // (duplicate column / index already exists) — bricking the database
      // permanently since every future launch hits the same cached
      // migration error. Wrapping in a transaction makes the whole upgrade
      // atomic: a crash mid-way rolls back to the pre-upgrade schema and the
      // next launch retries cleanly from scratch.
      await transaction(() async {
        await _runMigrationSteps(m, from);
      });
    },
    beforeOpen: (details) async {
      // SQLite disables foreign-key enforcement per-connection by default;
      // drift does not turn it on for us. Without this the .references()
      // constraint on activity_points is inert metadata. Enabling it only
      // affects new statements — existing rows are not re-validated, so
      // this is safe to switch on for upgrading users.
      await customStatement('PRAGMA foreign_keys = ON');
      if (details.wasCreated) {
        await into(preferences).insert(
          PreferencesCompanion.insert(
            mapTheme: MapThemeColumn.dark,
            mapLanguage: MapLanguageColumn.en,
            accuracyInMeters: 0,
          ),
        );
      }
    },
  );

  Future<void> _runMigrationSteps(Migrator m, int from) async {
    // Each `if (from < N)` block runs in order for users coming from an
    // earlier version. Pulled out of the onUpgrade closure purely so it can
    // be wrapped in the transaction() call above without an extra level of
    // nesting; still an instance method (not static) so it keeps access to
    // the table getters (preferences, activities, ...) and update() that
    // _$LocalDatabase generates on `this`.
    if (from < 2) {
      // v2: add hasCompletedOnboarding + uiLocale + lastShownChangelogVersion
      // to preferences and index hot foreign-key columns. Existing users
      // default to hasCompletedOnboarding=true so they don't see the wizard
      // on upgrade; uiLocale stays null (= follow device locale);
      // lastShownChangelogVersion stays null on the first run after this
      // migration — main.dart writes the current version so the changelog
      // doesn't pop for existing users on the upgrade introducing this
      // feature.
      await m.addColumn(preferences, preferences.hasCompletedOnboarding);
      await m.addColumn(preferences, preferences.uiLocale);
      await m.addColumn(preferences, preferences.lastShownChangelogVersion);
      await (update(preferences)).write(
        // hasCompletedOnboarding=true: existing users skip the wizard.
        // lastShownChangelogVersion='0.0.0' sentinel: forces the changelog
        // page on next launch so upgrading users see the current release
        // notes (changelogReleases lists newest-first).
        // Fresh installs take the beforeOpen path below instead — the row
        // is inserted with both fields at their column defaults (false +
        // null), and a null lastShownChangelogVersion suppresses the
        // changelog until the wizard stamps the current version.
        const PreferencesCompanion(
          hasCompletedOnboarding: Value(true),
          lastShownChangelogVersion: Value('0.0.0'),
        ),
      );
      // Indices on hot columns: foreign keys + the startedAt column the
      // activities list page sorts by on every fetch. Fresh installs get
      // them via m.createAll(); v1 users need them created explicitly.
      // (trace_points' index used to be created here too — moot since v8
      // drops that table outright for everyone.)
      await m.createIndex(idxActivityPointsActivityId);
      await m.createIndex(idxActivitiesStartedAt);
    }
    if (from < 3) {
      // v3: opt-out flag for the GitHub update check. Column default (true)
      // applies to the existing row, preserving today's behaviour.
      await m.addColumn(preferences, preferences.checkUpdates);
    }
    if (from < 4) {
      // v4: denormalised activity aggregates. Default -1 marks existing
      // rows as "not computed" — they're backfilled lazily the first time
      // the activities list loads them.
      await m.addColumn(activities, activities.distanceMeters);
      await m.addColumn(activities, activities.activeDurationMs);
    }
    if (from < 5) {
      // v5: per-fix GPS quality metadata (accuracy, verticalAccuracy).
      // Both nullable with no default — existing points simply have
      // "unknown" quality, which every reader already treats as "trust it
      // fully" (GpsQualityFilter only rejects on a *present* oversized
      // value; the elevation-gain smoothing in activity_entity.dart falls
      // back to the pre-v5 raw-sum algorithm whenever a segment has no
      // quality data at all). See docs/AUDIT-2026-07.md §4.
      await m.addColumn(activityPoints, activityPoints.accuracy);
      await m.addColumn(activityPoints, activityPoints.verticalAccuracy);
    }
    if (from < 6) {
      // v6: opt-out for map tile fetches (viewport-location privacy —
      // see preferences_table.dart doc on the column). Default true
      // preserves existing behaviour for upgrading users.
      await m.addColumn(preferences, preferences.mapTilesEnabled);
    }
    if (from < 7) {
      // v7: runtime-toggleable lock-screen visibility (see
      // preferences_table.dart doc on the column). Default true preserves
      // existing behaviour for upgrading users.
      await m.addColumn(preferences, preferences.showOnLockScreen);
    }
    if (from < 8) {
      // v8: drop the trace_points/trace_metadatas tables. The feature
      // they backed (persisting third-party OSM traces fetched while
      // panning the map) was removed — the store path had no reader and
      // grew unbounded, retaining third-party GPS data on disk at odds
      // with the app's privacy stance (see GetTracesUseCase). Users who
      // panned the map before this fix may have accumulated rows here;
      // dropping the tables purges that residual data rather than just
      // leaving the code path dead. Points first: it has the FK onto
      // metadata.
      await m.deleteTable('trace_points');
      await m.deleteTable('trace_metadatas');
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.sqlite'));
    // Run SQLite on a background isolate so per-fix writes and — more
    // importantly — loading every point of a multi-hour activity (24 h at one
    // fix / 5 s ≈ 17k rows) never block the UI isolate and jank the map /
    // activity list. createInBackground spawns a dedicated isolate and
    // marshals statements to it; the API is otherwise identical.
    return NativeDatabase.createInBackground(file);
  });
}
