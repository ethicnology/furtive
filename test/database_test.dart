import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/datasources/preferences_local_data_source.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/core/models/preferences_model.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v2 -> current migration', () {
    test('adds new columns with defaults and preserves existing rows',
        () async {
      // Build a v2-shaped database and stamp user_version = 2 so opening
      // LocalDatabase runs every onUpgrade step in sequence (2->3->4).
      final raw = sqlite3.openInMemory();
      raw.execute('''
        CREATE TABLE preferences (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          map_theme TEXT NOT NULL,
          map_language TEXT NOT NULL,
          accuracy_in_meters INTEGER NOT NULL,
          has_completed_onboarding INTEGER NOT NULL DEFAULT 0
            CHECK ("has_completed_onboarding" IN (0, 1)),
          ui_locale TEXT NULL,
          last_shown_changelog_version TEXT NULL
        );
      ''');
      raw.execute('''
        CREATE TABLE activities (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          started_at INTEGER NOT NULL,
          stopped_at INTEGER NULL
        );
      ''');
      raw.execute('''
        INSERT INTO preferences
          (id, map_theme, map_language, accuracy_in_meters,
           has_completed_onboarding, ui_locale, last_shown_changelog_version)
        VALUES (1, 'white', 'en', 0, 1, 'fr', '1.1.0');
      ''');
      raw.execute('''
        INSERT INTO activities
          (id, name, description, created_at, started_at, stopped_at)
        VALUES ('old', 'Track', '', 1000, 1000, 2000);
      ''');
      raw.execute('PRAGMA user_version = 2;');

      final db = LocalDatabase.forTesting(NativeDatabase.opened(raw));
      addTearDown(db.close);

      // First query triggers the migration.
      final prefs =
          await (db.select(db.preferences)..where((t) => t.id.equals(1)))
              .getSingle();

      expect(db.schemaVersion, 4);
      // Existing preferences survive untouched.
      expect(prefs.mapTheme, MapThemeColumn.white);
      expect(prefs.hasCompletedOnboarding, isTrue);
      expect(prefs.uiLocale, 'fr');
      expect(prefs.lastShownChangelogVersion, '1.1.0');
      // v3 column present with its default.
      expect(prefs.checkUpdates, isTrue);

      // v4 aggregate columns added with the -1 "not computed" sentinel; the
      // existing activity row is preserved.
      final activity =
          await (db.select(db.activities)..where((t) => t.id.equals('old')))
              .getSingle();
      expect(activity.name, 'Track');
      expect(activity.distanceMeters, -1);
      expect(activity.activeDurationMs, -1);
    });
  });

  group('fresh database (onCreate + beforeOpen)', () {
    late LocalDatabase db;

    setUp(() {
      db = LocalDatabase.forTesting(NativeDatabase.memory());
      if (getIt.isRegistered<LocalDatabase>()) {
        getIt.unregister<LocalDatabase>();
      }
      getIt.registerSingleton<LocalDatabase>(db);
    });

    tearDown(() async {
      await db.close();
      await getIt.reset();
    });

    test('seeds a default preferences row with checkUpdates = true', () async {
      final row = await (db.select(
        db.preferences,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(row.mapTheme, MapThemeColumn.dark);
      expect(row.checkUpdates, isTrue);
      expect(row.hasCompletedOnboarding, isFalse);
    });

    test('foreign keys are enforced (orphan point insert rejected)', () async {
      expect(
        () => db
            .into(db.activityPoints)
            .insert(
              ActivityPointsCompanion.insert(
                activityId: 'does-not-exist',
                latitude: 1,
                longitude: 1,
                elevation: 0,
                time: DateTime.utc(2026),
                status: ActivityPointsStatusColumn.active,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('store() drops non-finite points but keeps the activity', () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      await ds.store(
        ActivityModel(
          id: 'a1',
          name: 'Track',
          description: '',
          createdAt: t,
          startedAt: t,
          stoppedAt: t,
          points: [
            ActivityPointModel(
              latitude: double.nan,
              longitude: 2,
              elevation: 0,
              time: t,
              status: ActivityPointsStatusColumn.active,
            ),
            ActivityPointModel(
              latitude: 48.0,
              longitude: 2.0,
              elevation: 10,
              time: t.add(const Duration(seconds: 1)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      final fetched = await ds.fetchSingle('a1');
      expect(fetched.points.length, 1, reason: 'NaN point must be dropped');
      expect(fetched.points.single.latitude, 48.0);
    });

    test('fetchSummaries returns stored aggregates computed at store()',
        () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      await ds.store(
        ActivityModel(
          id: 's1',
          name: 'Track',
          description: '',
          createdAt: t,
          startedAt: t,
          stoppedAt: t.add(const Duration(seconds: 10)),
          points: [
            ActivityPointModel(
              latitude: 0,
              longitude: 0,
              elevation: 0,
              time: t,
              status: ActivityPointsStatusColumn.active,
            ),
            ActivityPointModel(
              latitude: 0,
              longitude: 0.001, // ~111 m east at the equator
              elevation: 0,
              time: t.add(const Duration(seconds: 10)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      final summaries = await ds.fetchSummaries();
      expect(summaries.length, 1);
      expect(summaries.single.activeDistanceMeters, closeTo(111.32, 1));
      expect(summaries.single.activeDuration, const Duration(seconds: 10));
    });

    test('in-progress activity (no stoppedAt) shows live stats, unpersisted',
        () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      // Mid-recording: points exist but the activity hasn't been ceased.
      await ds.store(
        ActivityModel(
          id: 'live',
          name: 'Track',
          description: '',
          createdAt: t,
          startedAt: t,
          stoppedAt: null,
          points: [
            ActivityPointModel(
              latitude: 0,
              longitude: 0,
              elevation: 0,
              time: t,
              status: ActivityPointsStatusColumn.active,
            ),
            ActivityPointModel(
              latitude: 0,
              longitude: 0.001,
              elevation: 0,
              time: t.add(const Duration(seconds: 10)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      // The list shows live-computed distance, not 0.
      final summaries = await ds.fetchSummaries();
      expect(summaries.single.activeDistanceMeters, closeTo(111.32, 1));

      // ...and the row keeps the -1 sentinel (not persisted) so it recomputes
      // again next time until the activity is ceased.
      final row = await (db.select(
        db.activities,
      )..where((a) => a.id.equals('live'))).getSingle();
      expect(row.distanceMeters, -1);
      expect(row.activeDurationMs, -1);
    });

    test('cease() persists aggregates and stamps stoppedAt', () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      await ds.store(
        ActivityModel(
          id: 'c1',
          name: 'Track',
          description: '',
          createdAt: t,
          startedAt: t,
          stoppedAt: null, // in progress
          points: [
            ActivityPointModel(
              latitude: 0,
              longitude: 0,
              elevation: 0,
              time: t,
              status: ActivityPointsStatusColumn.active,
            ),
            ActivityPointModel(
              latitude: 0,
              longitude: 0.001,
              elevation: 0,
              time: t.add(const Duration(seconds: 10)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      await ds.cease('c1');

      final row = await (db.select(
        db.activities,
      )..where((a) => a.id.equals('c1'))).getSingle();
      expect(row.stoppedAt, isNotNull);
      // Aggregates are now persisted (no longer the -1 sentinel).
      expect(row.distanceMeters, closeTo(111.32, 1));
      expect(row.activeDurationMs, const Duration(seconds: 10).inMilliseconds);
    });

    test('preferences round-trip preserves all fields incl. checkUpdates',
        () async {
      final ds = PreferencesLocalDataSource();
      await ds.store(
        PreferencesModel(
          mapTheme: MapThemeColumn.white,
          mapLanguage: MapLanguageColumn.en,
          accuracyInMeters: 0,
          hasCompletedOnboarding: true,
          uiLocale: 'de',
          lastShownChangelogVersion: '1.2.0',
          checkUpdates: false,
        ),
      );

      final read = await ds.fetch();
      expect(read.mapTheme, MapThemeColumn.white);
      expect(read.hasCompletedOnboarding, isTrue);
      expect(read.uiLocale, 'de');
      expect(read.lastShownChangelogVersion, '1.2.0');
      expect(read.checkUpdates, isFalse);
    });

    test('delete removes the activity and its points', () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      await ds.store(
        ActivityModel(
          id: 'a2',
          name: 'Track',
          description: '',
          createdAt: t,
          startedAt: t,
          stoppedAt: t,
          points: [
            ActivityPointModel(
              latitude: 48,
              longitude: 2,
              elevation: 0,
              time: t,
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );
      await ds.delete('a2');

      final remainingPoints = await db.select(db.activityPoints).get();
      expect(remainingPoints, isEmpty);
      final remainingActivities = await db.select(db.activities).get();
      expect(remainingActivities, isEmpty);
    });
  });
}
