import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:furtive/core/database/tables/activities_table.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables/trace_metadata_table.dart';
import 'tables/trace_points_table.dart';

part 'local_database.g.dart';

@DriftDatabase(
  tables: [
    TraceMetadatas,
    TracePoints,
    Activities,
    ActivityPoints,
    Preferences,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase() : super(_openConnection());

  /// Inject a query executor (e.g. `NativeDatabase.memory()`) for tests.
  LocalDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async => await m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      // Schema migrations live here. Each `if (from < N)` block runs in order
      // for users coming from an earlier version.
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
        await m.createIndex(idxActivityPointsActivityId);
        await m.createIndex(idxTracePointsTraceId);
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
    },
    beforeOpen: (details) async {
      // SQLite disables foreign-key enforcement per-connection by default;
      // drift does not turn it on for us. Without this the .references()
      // constraints on activity_points / trace_points are inert metadata.
      // Enabling it only affects new statements — existing rows are not
      // re-validated, so this is safe to switch on for upgrading users.
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
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.sqlite'));
    return NativeDatabase(file);
  });
}
