import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/datasources/preferences_local_data_source.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/usecases/ensure_background_tracking_use_case.dart';
import 'package:furtive/core/usecases/get_map_tile_url_use_case.dart';
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
/// The real GetMapConfigUseCase is used rather than a stub: with no
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
    getMapConfig: GetMapConfigUseCase(
      preferences: PreferencesRepository(
        local: PreferencesLocalDataSource(db: db),
      ),
    ),
    location: location,
    positionStream: PositionStreamController(location: location, clock: clock),
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
      expect(bloc.state.style, isNull, reason: 'tileless build');
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
        PositionStreamController.staleThreshold + const Duration(seconds: 5),
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
