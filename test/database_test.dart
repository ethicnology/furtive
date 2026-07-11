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
      // activity_points predates every migration exercised here — v2/v3/v4
      // never touched it — but v5 (below) adds columns to it, so the fake
      // "device on v2" schema needs it present, as a real device would.
      raw.execute('''
        CREATE TABLE activity_points (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          elevation REAL NOT NULL,
          time INTEGER NOT NULL,
          activity_id TEXT NOT NULL REFERENCES activities (id),
          status TEXT NOT NULL
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
      raw.execute('''
        INSERT INTO activity_points
          (latitude, longitude, elevation, time, activity_id, status)
        VALUES (48.0, 2.0, 100, 1000, 'old', 'active');
      ''');
      raw.execute('PRAGMA user_version = 2;');

      final db = LocalDatabase.forTesting(NativeDatabase.opened(raw));
      addTearDown(db.close);

      // First query triggers the migration.
      final prefs =
          await (db.select(db.preferences)..where((t) => t.id.equals(1)))
              .getSingle();

      expect(db.schemaVersion, 7);
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

      // v5 quality columns added as NULL ("unknown"), not backfilled; the
      // existing point survives with its original lat/lon/elevation intact.
      final point =
          await (db.select(db.activityPoints)
                ..where((t) => t.activityId.equals('old')))
              .getSingle();
      expect(point.latitude, 48.0);
      expect(point.accuracy, isNull);
      expect(point.verticalAccuracy, isNull);

      // v6 map-tiles opt-out added with its true default — an upgrading
      // user keeps today's tile-fetching behaviour unless they opt out.
      expect(prefs.mapTilesEnabled, isTrue);

      // v7 lock-screen-visibility toggle, same true-default treatment.
      expect(prefs.showOnLockScreen, isTrue);
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

    test('score() drops a late fix for an already-ceased activity', () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      await ds.store(
        ActivityModel(
          id: 's1',
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
          ],
        ),
      );

      await ds.cease('s1');

      // A GPS fix that was already queued when the user tapped Stop: it must be
      // dropped, not landed past stoppedAt where it would desync the stored
      // aggregates from the points actually in the DB.
      await ds.score('s1', [
        ActivityPointModel(
          latitude: 0,
          longitude: 0.001,
          elevation: 0,
          time: t.add(const Duration(seconds: 10)),
          status: ActivityPointsStatusColumn.active,
        ),
      ]);

      final single = await ds.fetchSingle('s1');
      expect(single.points.length, 1);
    });

    test('fetchOngoing returns the newest un-ceased activity with its points',
        () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      // The live run must have a *recent* last fix to be resumable: an ongoing
      // row whose newest fix is older than the stale window is treated as an
      // abandoned/crashed recording and auto-ceased instead. Anchor it to now.
      final now = DateTime.now().toUtc();

      // An older ceased run — must be ignored.
      await ds.store(
        ActivityModel(
          id: 'ceased',
          name: 'Track',
          description: '',
          createdAt: t,
          startedAt: t,
          stoppedAt: t.add(const Duration(minutes: 30)),
          points: const [],
        ),
      );
      // The run the user is mid-recording when the OS kills the app.
      await ds.store(
        ActivityModel(
          id: 'live',
          name: 'Track',
          description: '',
          createdAt: now.subtract(const Duration(minutes: 5)),
          startedAt: now.subtract(const Duration(minutes: 5)),
          stoppedAt: null,
          points: [
            ActivityPointModel(
              latitude: 0,
              longitude: 0,
              elevation: 0,
              time: now.subtract(const Duration(minutes: 5)),
              status: ActivityPointsStatusColumn.active,
            ),
            ActivityPointModel(
              latitude: 0,
              longitude: 0.001,
              elevation: 0,
              time: now.subtract(const Duration(minutes: 4, seconds: 50)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      final ongoing = await ds.fetchOngoing();
      expect(ongoing, isNotNull);
      expect(ongoing!.id, 'live');
      expect(ongoing.stoppedAt, isNull);
      // Points written before the kill are restored for the resumed run.
      expect(ongoing.points.length, 2);
    });

    test('fetchOngoing auto-ceases a stale ongoing run and returns null',
        () async {
      final ds = ActivityLocalDataSource();
      // Last fix well beyond the 12h stale window: an abandoned/crashed
      // recording, not something to resume as a bogus multi-day live run.
      final old = DateTime.now().toUtc().subtract(const Duration(days: 2));
      await ds.store(
        ActivityModel(
          id: 'stale',
          name: 'Track',
          description: '',
          createdAt: old,
          startedAt: old,
          stoppedAt: null,
          points: [
            ActivityPointModel(
              latitude: 0,
              longitude: 0,
              elevation: 0,
              time: old,
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      expect(await ds.fetchOngoing(), isNull);
      // The stale run is finalised, not left dangling as "in progress".
      final single = await ds.fetchSingle('stale');
      expect(single.stoppedAt, isNotNull);
    });

    test('fetchOngoing auto-ceases older orphans, resumes only the newest',
        () async {
      final ds = ActivityLocalDataSource();
      final now = DateTime.now().toUtc();

      // An older orphan (never ceased) left by a prior kill.
      await ds.store(
        ActivityModel(
          id: 'orphan',
          name: 'Track',
          description: '',
          createdAt: now.subtract(const Duration(hours: 2)),
          startedAt: now.subtract(const Duration(hours: 2)),
          stoppedAt: null,
          points: [
            ActivityPointModel(
              latitude: 0,
              longitude: 0,
              elevation: 0,
              time: now.subtract(const Duration(hours: 2)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );
      // The newest ongoing run — the resume candidate.
      await ds.store(
        ActivityModel(
          id: 'newest',
          name: 'Track',
          description: '',
          createdAt: now.subtract(const Duration(minutes: 2)),
          startedAt: now.subtract(const Duration(minutes: 2)),
          stoppedAt: null,
          points: [
            ActivityPointModel(
              latitude: 0,
              longitude: 0,
              elevation: 0,
              time: now.subtract(const Duration(minutes: 2)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      final ongoing = await ds.fetchOngoing();
      expect(ongoing, isNotNull);
      expect(ongoing!.id, 'newest');
      // The older orphan is finalised so it stops being "in progress" forever.
      final orphan = await ds.fetchSingle('orphan');
      expect(orphan.stoppedAt, isNotNull);
    });

    test('fetchOngoing returns null when every activity is ceased', () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      await ds.store(
        ActivityModel(
          id: 'done',
          name: 'Track',
          description: '',
          createdAt: t,
          startedAt: t,
          stoppedAt: t.add(const Duration(minutes: 5)),
          points: const [],
        ),
      );

      expect(await ds.fetchOngoing(), isNull);
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
