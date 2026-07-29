import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/datasources/preferences_local_data_source.dart';
import 'package:flutter/foundation.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/facades/compass_facade.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/usecases/ensure_background_tracking_use_case.dart';
import 'package:furtive/core/usecases/get_map_style_url_use_case.dart';
import 'package:furtive/core/usecases/score_activity_use_case.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/features/map/position_stream_controller.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';

import 'support/fakes.dart';

/// MapBloc is now map presentation plus the wiring between the position stream
/// and the recorder. These tests cover that wiring; the recording rules live in
/// recording_bloc_test.dart and the stream lifecycle in
/// position_stream_controller_test.dart.
///
/// The real GetMapStyleUrlUseCase is used rather than a stub: with no
/// PROTOMAPS_KEY compiled in (the case under `flutter test`) it takes the
/// genuine tileless path and returns a null style, which is exactly what the
/// keyless FOSS build does at runtime.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late FixedClock clock;
  late FakeLocationRepository location;
  late RecordingBloc recording;
  final start = DateTime.utc(2026, 7, 26, 10);

  setUp(() {
    db = inMemoryDatabase();
    clock = FixedClock(start);
    location = FakeLocationRepository(currentLocation: fixAt(start));
    final repo = ActivityRepository(
      local: ActivityLocalDataSource(db: db, clock: clock),
      clock: clock,
    );
    recording = RecordingBloc(
      activities: repo,
      score: ScoreActivityUseCase(activities: repo, clock: clock),
      ensureBackgroundTracking: EnsureBackgroundTrackingUseCase(
        location: location,
      ),
      clock: clock,
    );
  });

  tearDown(() async {
    await recording.close();
    await location.dispose();
    await db.close();
  });

  MapBloc buildBloc() => MapBloc(
    recording: recording,
    getMapStyleUrl: GetMapStyleUrlUseCase(
      preferences: PreferencesRepository(
        local: PreferencesLocalDataSource(db: db),
      ),
    ),
    location: location,
    positionStream: PositionStreamController(location: location, clock: clock),
    // Backed by the in-memory database like the style use case above: MapBloc
    // reads the recording preferences on InitMap, and the default would reach
    // for the getIt-registered production database.
    preferences: PreferencesRepository(
      local: PreferencesLocalDataSource(db: db),
    ),
    // Reported as a non-Android platform so the facade short-circuits: the
    // compass is a native sensor stream with no meaning in a unit test, and
    // its own suite covers the smoothing.
    compass: CompassFacade(platform: TargetPlatform.linux),
  );

  Future<void> seedOngoing(String id, DateTime startedAt) {
    return ActivityLocalDataSource(db: db, clock: clock).store(
      ActivityModel(
        id: id,
        name: 'Track',
        description: '',
        createdAt: startedAt,
        startedAt: startedAt,
        stoppedAt: null,
        points: [
          ActivityPointModel(
            latitude: 48.85,
            longitude: 2.35,
            elevation: 0,
            time: startedAt,
            status: ActivityPointsStatusColumn.active,
          ),
        ],
      ),
    );
  }

  blocTest<MapBloc, MapState>(
    'InitMap opens the stream, fetches a fix and settles with no loading status',
    build: buildBloc,
    act: (bloc) => bloc.add(const InitMap()),
    wait: const Duration(milliseconds: 100),
    verify: (bloc) {
      expect(location.positionStreamOpenCount, 1);
      expect(bloc.state.userLocation, isNotNull);
      expect(bloc.state.loadingStatus, isNull);
      expect(bloc.state.styleUrl, isNull, reason: 'tileless build');
    },
  );

  blocTest<MapBloc, MapState>(
    'InitMap still resumes an ongoing activity when the one-shot GPS fix fails '
    '— cold GPS right after an unlock must not strand a live recording',
    setUp: () => seedOngoing('ongoing1', start),
    build: () {
      location.failCurrentLocation = true;
      return buildBloc();
    },
    act: (bloc) => bloc.add(const InitMap()),
    wait: const Duration(milliseconds: 150),
    verify: (bloc) {
      expect(recording.state.activity?.id, 'ongoing1');
      expect(bloc.state.userLocation, isNull);
      expect(bloc.state.loadingStatus, isNull);
    },
  );

  blocTest<MapBloc, MapState>(
    'two InitMap events in quick succession do not double-open the stream',
    build: buildBloc,
    act: (bloc) {
      bloc.add(const InitMap());
      bloc.add(const InitMap());
    },
    wait: const Duration(milliseconds: 150),
    verify: (bloc) => expect(location.positionStreamOpenCount, 1),
    errors: () => isEmpty,
  );

  test('a fix is scored only when a recording is running', () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);
    bloc.add(const InitMap());
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // Nothing recording: the fix updates the map but is not persisted.
    location.fixes.add(fixAt(start.add(const Duration(seconds: 1))));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bloc.state.userLocation, isNotNull);
    expect(recording.state.activity, isNull);

    // Now record, and the next fix must reach the activity.
    recording.add(const StartRecording());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    location.fixes.add(fixAt(start.add(const Duration(seconds: 6))));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(recording.state.activity!.points, isNotEmpty);
  });

  test('a vague fix updates the cursor but not the active trace', () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);
    bloc.add(const InitMap());
    await Future<void>.delayed(const Duration(milliseconds: 120));

    recording.add(const StartRecording(activityType: ActivityTypeEntity.run));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final vague = fixAt(start.add(const Duration(seconds: 5)), accuracy: 150);
    location.fixes.add(vague);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(bloc.state.userLocation, vague, reason: 'the cursor may degrade');
    expect(
      recording.state.activity!.points,
      isEmpty,
      reason: '150 m is outside the running profile recording tolerance',
    );

    location.fixes.add(
      fixAt(start.add(const Duration(seconds: 10)), accuracy: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(recording.state.activity!.points, hasLength(1));
  });

  test('a vague paused fix is kept as a pause boundary', () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);
    bloc.add(const InitMap());
    await Future<void>.delayed(const Duration(milliseconds: 120));

    recording.add(const StartRecording(activityType: ActivityTypeEntity.run));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    recording.add(const PauseRecording());
    await Future<void>.delayed(const Duration(milliseconds: 40));

    location.fixes.add(
      fixAt(start.add(const Duration(seconds: 5)), accuracy: 150),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(recording.state.activity!.points, hasLength(1));
    expect(
      recording.state.activity!.points.single.status,
      ActivityPointStatusEntity.paused,
      reason: 'pause boundaries are excluded from active distance',
    );
  });

  group('activity profile reaches the GPS stream', () {
    test('starting a recording re-opens the stream with the activity profile, '
        'and stopping returns it to the idle one', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const InitMap());
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Idle: the map's own stream, on the permissive generic profile.
      expect(
        location.lastTuning?.plausibleSpeedMps,
        MovementProfileEntity.generic.tuning.plausibleSpeedMps,
      );
      final openedWhileIdle = location.positionStreamOpenCount;

      recording.add(
        const StartRecording(activityType: ActivityTypeEntity.car),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Without this the activity would carry a label and nothing else: the
      // sampling interval and the quality gate are properties of the platform
      // request, so they only change if the stream is actually reopened.
      expect(
        location.positionStreamOpenCount,
        greaterThan(openedWhileIdle),
        reason: 'the stream must be reopened for the new profile to apply',
      );
      expect(
        location.lastTuning?.plausibleSpeedMps,
        MovementProfileEntity.road.tuning.plausibleSpeedMps,
      );

      recording.add(const StopRecording());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        location.lastTuning?.plausibleSpeedMps,
        MovementProfileEntity.generic.tuning.plausibleSpeedMps,
      );
    });

    test('the recording-detail preference reaches the GPS layer', () async {
      // A setting that is stored and displayed but changes nothing is how the
      // dead `accuracy_in_meters` column happened. This one has to bite.
      final prefs = PreferencesRepository(
        local: PreferencesLocalDataSource(db: db),
      );
      await prefs.store(
        (await prefs.fetch()).copyWith(
          recordingDetail: RecordingDetailEntity.precise,
        ),
      );

      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const InitMap());
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(location.lastDetail, RecordingDetailEntity.precise);
    });

    test('a preferences change is picked up without re-initialising the map', () async {
      // Found on device: the control side and the sampling detail were only
      // read at InitMap, so flipping the switch in Preferences appeared to do
      // nothing until the app was restarted. InitMap is the wrong hammer here
      // — it re-resolves the basemap style and flashes the loading UI for a
      // change that only moves buttons.
      final prefs = PreferencesRepository(
        local: PreferencesLocalDataSource(db: db),
      );
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const InitMap());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(bloc.state.mapControlsOnLeft, isFalse);
      final styleAfterInit = bloc.state.styleUrl;

      await prefs.store((await prefs.fetch()).copyWith(mapControlsOnLeft: true));
      bloc.add(const RefreshRecordingPreferences());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.mapControlsOnLeft, isTrue);
      expect(bloc.state.styleUrl, styleAfterInit);
      expect(bloc.state.loadingStatus, isNull, reason: 'no loading flash');
    });

    test('the chosen type is stamped on the stored activity', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const InitMap());
      await Future<void>.delayed(const Duration(milliseconds: 120));

      recording.add(
        const StartRecording(activityType: ActivityTypeEntity.swim),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        recording.state.activity!.activityType,
        ActivityTypeEntity.swim,
      );
    });

    test(
      'a failed profile reopen is surfaced and retried immediately',
      () async {
        final bloc = buildBloc();
        addTearDown(bloc.close);
        bloc.add(const InitMap());
        await Future<void>.delayed(const Duration(milliseconds: 120));

        location.positionStreamFailuresRemaining = 1;
        recording.add(
          const StartRecording(activityType: ActivityTypeEntity.car),
        );
        await Future<void>.delayed(const Duration(milliseconds: 180));

        expect(
          bloc.state.error,
          isNotNull,
          reason: 'trace loss must be visible',
        );
        expect(
          location.positionStreamOpenAttempts,
          3,
          reason: 'initial open, failed profile open, immediate watchdog retry',
        );
        expect(location.positionStreamOpenCount, 2);
        expect(
          location.lastTuning?.plausibleSpeedMps,
          MovementProfileEntity.road.tuning.plausibleSpeedMps,
        );
      },
    );
  });

  group('EnsureTracking', () {
    test('a healthy stream is left alone', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const InitMap());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      location.fixes.add(fixAt(start));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      bloc.add(const EnsureTracking());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(location.positionStreamOpenCount, 1);
    });

    test('a silently suspended stream is reopened', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const InitMap());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      location.fixes.add(fixAt(start));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      clock.advance(
        PositionStreamController.minimumStaleThreshold + const Duration(seconds: 5),
      );
      bloc.add(const EnsureTracking());
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(location.positionStreamOpenCount, 2);
    });

    test(
      'a stale stream during an active recording raises the tracking-gap banner',
      () async {
        final bloc = buildBloc();
        addTearDown(bloc.close);
        bloc.add(const InitMap());
        await Future<void>.delayed(const Duration(milliseconds: 120));
        location.fixes.add(fixAt(start));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        recording.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 60));

        clock.advance(const Duration(minutes: 5));
        bloc.add(const EnsureTracking());
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(recording.state.trackingGap, isNotNull);
        expect(recording.state.trackingGap!.inMinutes, 5);
      },
    );

    test('no banner when nothing is being recorded — a frozen blue dot alone '
        'is reopened silently', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const InitMap());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      location.fixes.add(fixAt(start));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      clock.advance(const Duration(minutes: 5));
      bloc.add(const EnsureTracking());
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(recording.state.trackingGap, isNull);
      expect(location.positionStreamOpenCount, 2);
    });
  });

  blocTest<MapBloc, MapState>(
    'follow-user toggles',
    build: buildBloc,
    act: (bloc) {
      bloc.add(const ToggleFollowUser());
      bloc.add(const StopFollowingUser());
    },
    wait: const Duration(milliseconds: 40),
    verify: (bloc) => expect(bloc.state.isFollowingUser, isFalse),
  );
}
