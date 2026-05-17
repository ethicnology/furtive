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

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async => await m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      // Schema migrations live here. Each `if (from < N)` block runs in order
      // for users coming from an earlier version.
      if (from < 2) {
        // v2: add hasCompletedOnboarding to preferences (for the first-launch
        // wizard). Existing users default to true so they don't see the
        // wizard on upgrade.
        await m.addColumn(preferences, preferences.hasCompletedOnboarding);
        await (update(preferences)).write(
          PreferencesCompanion(hasCompletedOnboarding: Value(true)),
        );
      }
    },
    beforeOpen: (details) async {
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
