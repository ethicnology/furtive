import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/datasources/preferences_local_data_source.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/core/models/preferences_model.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v2 -> current migration', () {
    test(
      'adds new columns with defaults and preserves existing rows',
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
        final prefs = await (db.select(
          db.preferences,
        )..where((t) => t.id.equals(1))).getSingle();

        expect(db.schemaVersion, 8);
        // Existing preferences survive untouched.
        expect(prefs.mapTheme, MapThemeColumn.white);
        expect(prefs.hasCompletedOnboarding, isTrue);
        expect(prefs.uiLocale, 'fr');
        expect(prefs.lastShownChangelogVersion, '1.1.0');
        // v3 column present with its default.
        expect(prefs.checkUpdates, isTrue);

        // v4 aggregate columns added with the -1 "not computed" sentinel; the
        // existing activity row is preserved.
        final activity = await (db.select(
          db.activities,
        )..where((t) => t.id.equals('old'))).getSingle();
        expect(activity.name, 'Track');
        expect(activity.distanceMeters, -1);
        expect(activity.activeDurationMs, -1);

        // v5 quality columns added as NULL ("unknown"), not backfilled; the
        // existing point survives with its original lat/lon/elevation intact.
        final point = await (db.select(
          db.activityPoints,
        )..where((t) => t.activityId.equals('old'))).getSingle();
        expect(point.latitude, 48.0);
        expect(point.accuracy, isNull);
        expect(point.verticalAccuracy, isNull);

        // v6 map-tiles opt-out added with its true default — an upgrading
        // user keeps today's tile-fetching behaviour unless they opt out.
        expect(prefs.mapTilesEnabled, isTrue);

        // v7 lock-screen-visibility toggle, same true-default treatment.
        expect(prefs.showOnLockScreen, isTrue);
      },
    );

    test(
      'v8 drops trace_points/trace_metadatas, purging any residual '
      'third-party trace data the removed local-store feature accumulated',
      () async {
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
          last_shown_changelog_version TEXT NULL,
          check_updates INTEGER NOT NULL DEFAULT 1
            CHECK ("check_updates" IN (0, 1)),
          map_tiles_enabled INTEGER NOT NULL DEFAULT 1
            CHECK ("map_tiles_enabled" IN (0, 1)),
          show_on_lock_screen INTEGER NOT NULL DEFAULT 1
            CHECK ("show_on_lock_screen" IN (0, 1))
        );
      ''');
        raw.execute('''
        CREATE TABLE activities (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          started_at INTEGER NOT NULL,
          stopped_at INTEGER NULL,
          distance_meters REAL NOT NULL DEFAULT -1,
          active_duration_ms INTEGER NOT NULL DEFAULT -1
        );
      ''');
        raw.execute('''
        CREATE TABLE activity_points (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          elevation REAL NOT NULL,
          time INTEGER NOT NULL,
          activity_id TEXT NOT NULL REFERENCES activities (id),
          status TEXT NOT NULL,
          accuracy REAL NULL,
          vertical_accuracy REAL NULL
        );
      ''');
        // The tables the removed local-trace-store feature used to write —
        // present on any real device that had panned the map before this
        // fix, with leftover third-party OSM data still in them.
        raw.execute('''
        CREATE TABLE trace_metadatas (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT NOT NULL,
          url TEXT NOT NULL
        );
      ''');
        raw.execute('''
        CREATE TABLE trace_points (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          elevation REAL NULL,
          time INTEGER NULL,
          trace_id INTEGER NOT NULL REFERENCES trace_metadatas (id)
        );
      ''');
        raw.execute('''
        INSERT INTO preferences (id, map_theme, map_language, accuracy_in_meters)
        VALUES (1, 'white', 'en', 0);
      ''');
        raw.execute('''
        INSERT INTO trace_metadatas (id, name, description, url)
        VALUES (1, 'Some OSM trace', '', 'https://example.com');
      ''');
        raw.execute('''
        INSERT INTO trace_points (latitude, longitude, trace_id)
        VALUES (48.0, 2.0, 1);
      ''');
        raw.execute('PRAGMA user_version = 7;');

        final db = LocalDatabase.forTesting(NativeDatabase.opened(raw));
        addTearDown(db.close);

        // First query triggers the migration.
        await (db.select(
          db.preferences,
        )..where((t) => t.id.equals(1))).getSingle();
        expect(db.schemaVersion, 8);

        final remainingTables = raw
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' AND "
              "name IN ('trace_points', 'trace_metadatas')",
            )
            .map((row) => row['name'] as String)
            .toList();
        expect(remainingTables, isEmpty);
      },
    );

    test(
      'v1 -> current: the from < 2 step (add columns, backfill, create '
      'indices) actually runs and survives a full replay to schemaVersion',
      () async {
        // v1 predates hasCompletedOnboarding/uiLocale/lastShownChangelogVersion
        // and the two hot-column indices — nothing in this suite exercises
        // the `if (from < 2)` block otherwise (every other fixture starts at
        // user_version 2 or 7).
        final raw = sqlite3.openInMemory();
        raw.execute('''
        CREATE TABLE preferences (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          map_theme TEXT NOT NULL,
          map_language TEXT NOT NULL,
          accuracy_in_meters INTEGER NOT NULL
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
        INSERT INTO preferences (id, map_theme, map_language, accuracy_in_meters)
        VALUES (1, 'dark', 'en', 0);
      ''');
        raw.execute('''
        INSERT INTO activities (id, name, description, created_at, started_at, stopped_at)
        VALUES ('v1', 'Track', '', 1000, 1000, 2000);
      ''');
        raw.execute('PRAGMA user_version = 1;');

        final db = LocalDatabase.forTesting(NativeDatabase.opened(raw));
        addTearDown(db.close);

        final prefs = await (db.select(
          db.preferences,
        )..where((t) => t.id.equals(1))).getSingle();

        expect(db.schemaVersion, 8);
        // v2 backfill: existing users skip onboarding and get the changelog
        // sentinel; fresh installs (not this path) get the column defaults.
        expect(prefs.hasCompletedOnboarding, isTrue);
        expect(prefs.lastShownChangelogVersion, '0.0.0');
        expect(prefs.uiLocale, isNull);
        // v3/v6/v7 defaults preserved through the full replay from v1.
        expect(prefs.checkUpdates, isTrue);
        expect(prefs.mapTilesEnabled, isTrue);
        expect(prefs.showOnLockScreen, isTrue);

        final activity = await (db.select(
          db.activities,
        )..where((t) => t.id.equals('v1'))).getSingle();
        expect(activity.distanceMeters, -1);

        // The v2 step's createIndex calls didn't throw / silently no-op.
        final indexNames = raw
            .select(
              "SELECT name FROM sqlite_master WHERE type='index' AND "
              "name IN ('idx_activity_points_activity_id', "
              "'idx_activities_started_at')",
            )
            .map((row) => row['name'] as String)
            .toList();
        expect(indexNames, hasLength(2));
      },
    );

    test('refuses to open a database with a newer schema version than '
        'this build knows about (downgrade guard)', () async {
      // Simulates sideloading an older APK/IPA over a DB written by a newer
      // version — without a guard, drift would silently no-op every
      // migration step and stamp the LOWER version into user_version,
      // corrupting the version bookkeeping (see M1 in the audit).
      final raw = sqlite3.openInMemory();
      raw.execute('''
        CREATE TABLE preferences (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          map_theme TEXT NOT NULL,
          map_language TEXT NOT NULL,
          accuracy_in_meters INTEGER NOT NULL
        );
      ''');
      raw.execute('PRAGMA user_version = 99;');

      final db = LocalDatabase.forTesting(NativeDatabase.opened(raw));
      addTearDown(db.close);

      expect(() => db.select(db.preferences).get(), throwsA(isA<StateError>()));
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

    test(
      'fetchSummaries returns stored aggregates computed at store()',
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
      },
    );

    test(
      'in-progress activity (no stoppedAt) shows live stats, unpersisted',
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
      },
    );

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

    test('signalLost boundary points survive a DB round-trip (regression: '
        'SQLite truncates DateTime to whole seconds, so the ±1µs boundary '
        'pair ties exactly with its anchor point once reloaded — this only '
        'segments correctly if the read is ordered `id ASC` and the entity '
        'sort is STABLE, breaking the tie by that insertion order)', () async {
      final ds = ActivityLocalDataSource();
      final t = DateTime.utc(2026, 1, 1, 12);
      // Mirrors ScoreActivityUseCase's gapFrom bracketing: an active run,
      // a signalLost pair duplicating the points either side of a 600 s
      // gap (offsets truncated away by SQLite, deliberately NOT set to
      // distinct seconds here — the whole point is that they tie), then
      // the active run resumes.
      await ds.store(
        ActivityModel(
          id: 'gap1',
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
            // signalLost boundary #1: duplicate of the point above.
            ActivityPointModel(
              latitude: 0,
              longitude: 0.001,
              elevation: 0,
              time: t.add(const Duration(seconds: 10)),
              status: ActivityPointsStatusColumn.signalLost,
            ),
            // signalLost boundary #2: duplicate of the point below.
            ActivityPointModel(
              latitude: 0,
              longitude: 0.011,
              elevation: 0,
              time: t.add(const Duration(seconds: 610)),
              status: ActivityPointsStatusColumn.signalLost,
            ),
            ActivityPointModel(
              latitude: 0,
              longitude: 0.011,
              elevation: 0,
              time: t.add(const Duration(seconds: 610)),
              status: ActivityPointsStatusColumn.active,
            ),
            ActivityPointModel(
              latitude: 0,
              longitude: 0.012,
              elevation: 0,
              time: t.add(const Duration(seconds: 620)),
              status: ActivityPointsStatusColumn.active,
            ),
          ],
        ),
      );

      final fetched = ActivityModel.toEntity(await ds.fetchSingle('gap1'));
      expect(fetched.segments.length, 3);
      expect(fetched.signalLostSegments.length, 1);
      // The 600 s gap must be excluded from active duration, not
      // silently folded back in by a misordered segment.
      expect(fetched.activeDuration, const Duration(seconds: 20));
      expect(fetched.signalLostDuration, const Duration(seconds: 600));

      // cease()'s persisted aggregate must agree with the live
      // recomputation above — this is exactly the stored-vs-live
      // divergence a misordered segment would introduce.
      await ds.cease('gap1');
      final row = await (db.select(
        db.activities,
      )..where((a) => a.id.equals('gap1'))).getSingle();
      expect(row.activeDurationMs, const Duration(seconds: 20).inMilliseconds);
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

    test(
      'fetchOngoing returns the newest un-ceased activity with its points',
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
      },
    );

    test(
      'fetchOngoing auto-ceases a stale ongoing run and returns null',
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
      },
    );

    test(
      'fetchOngoing auto-ceases older orphans, resumes only the newest',
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
      },
    );

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

    test(
      'preferences round-trip preserves all fields incl. checkUpdates',
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
      },
    );

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
