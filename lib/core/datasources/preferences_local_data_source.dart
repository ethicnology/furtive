import 'package:drift/drift.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/models/preferences_model.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/locator.dart';

class PreferencesLocalDataSource {
  /// [db] defaults to the app-wide singleton so production call sites stay
  /// `PreferencesLocalDataSource()`; tests inject an in-memory database.
  PreferencesLocalDataSource({LocalDatabase? db})
    : db = db ?? getIt.get<LocalDatabase>();

  final LocalDatabase db;

  Future<void> store(PreferencesModel preferences) async {
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion(
            id: const Value(1),
            mapTheme: Value(preferences.mapTheme),
            hasCompletedOnboarding: Value(preferences.hasCompletedOnboarding),
            uiLocale: Value(preferences.uiLocale),
            lastShownChangelogVersion: Value(
              preferences.lastShownChangelogVersion,
            ),
            mapTilesEnabled: Value(preferences.mapTilesEnabled),
            showOnLockScreen: Value(preferences.showOnLockScreen),
            mapControlsOnLeft: Value(preferences.mapControlsOnLeft),
            lastActivityType: Value(preferences.lastActivityType),
            recordingDetail: Value(preferences.recordingDetail),
          ),
        );
  }

  Future<PreferencesModel> fetch() async {
    var preferences = await (db.select(
      db.preferences,
    )..where((tbl) => tbl.id.equals(1))).getSingleOrNull();

    // The seed row is created in beforeOpen, but a partially-migrated or
    // externally-cleared DB could lack it. Re-seed defaults (forcing id=1)
    // rather than throwing — fetch() runs at startup and feeds the map config.
    if (preferences == null) {
      await db
          .into(db.preferences)
          .insertOnConflictUpdate(
            const PreferencesCompanion(
              id: Value(1),
              mapTheme: Value(MapThemeColumn.dark),
            ),
          );
      preferences = await (db.select(
        db.preferences,
      )..where((tbl) => tbl.id.equals(1))).getSingle();
    }

    return PreferencesModel(
      mapTheme: preferences.mapTheme,
      hasCompletedOnboarding: preferences.hasCompletedOnboarding,
      uiLocale: preferences.uiLocale,
      lastShownChangelogVersion: preferences.lastShownChangelogVersion,
      mapTilesEnabled: preferences.mapTilesEnabled,
      showOnLockScreen: preferences.showOnLockScreen,
      mapControlsOnLeft: preferences.mapControlsOnLeft,
      lastActivityType: preferences.lastActivityType,
      recordingDetail: preferences.recordingDetail,
    );
  }
}
