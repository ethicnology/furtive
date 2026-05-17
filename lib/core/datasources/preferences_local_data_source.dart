import 'package:drift/drift.dart';
import 'package:furtive/core/models/preferences_model.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/locator.dart';

class PreferencesLocalDataSource {
  final db = getIt.get<LocalDatabase>();

  PreferencesLocalDataSource();

  Future<void> store(PreferencesModel preferences) async {
    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion(
            id: const Value(1),
            mapTheme: Value(preferences.mapTheme),
            mapLanguage: Value(preferences.mapLanguage),
            accuracyInMeters: Value(preferences.accuracyInMeters),
            hasCompletedOnboarding: Value(preferences.hasCompletedOnboarding),
          ),
        );
  }

  Future<PreferencesModel> fetch() async {
    final preferences =
        await (db.select(db.preferences)
          ..where((tbl) => tbl.id.equals(1))).getSingle();

    return PreferencesModel(
      mapTheme: preferences.mapTheme,
      mapLanguage: preferences.mapLanguage,
      accuracyInMeters: preferences.accuracyInMeters,
      hasCompletedOnboarding: preferences.hasCompletedOnboarding,
    );
  }
}
