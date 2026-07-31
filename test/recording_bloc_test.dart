import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/usecases/ensure_background_tracking_use_case.dart';
import 'package:furtive/core/usecases/score_activity_use_case.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';
import 'package:furtive/features/recording/bloc/recording_state.dart';

import 'support/fakes.dart';

/// Coverage for the recording state machine — the logic that decides whether a
/// run survives an OS kill, and how much of the elapsed time was really spent
/// moving. Previously reachable by three tests because nothing in the old
/// MapBloc was injectable; a [Clock] plus constructor injection makes the 12 h
/// staleness window and the pause bookkeeping directly assertable.
void main() {
  late LocalDatabase db;
  late FixedClock clock;
  late FakeLocationRepository location;
  final start = DateTime.utc(2026, 7, 26, 10);

  setUp(() {
    db = inMemoryDatabase();
    clock = FixedClock(start);
    location = FakeLocationRepository(currentLocation: fixAt(start));
  });

  tearDown(() async {
    await location.dispose();
    await db.close();
  });

  ActivityRepository repository() => ActivityRepository(
    local: ActivityLocalDataSource(db: db, clock: clock),
    clock: clock,
  );

  RecordingBloc buildBloc() {
    final repo = repository();
    return RecordingBloc(
      activities: repo,
      score: ScoreActivityUseCase(activities: repo, clock: clock),
      ensureBackgroundTracking: EnsureBackgroundTrackingUseCase(
        location: location,
      ),
      clock: clock,
    );
  }

  Future<void> seedOngoing({
    required String id,
    required DateTime startedAt,
    DateTime? lastFixAt,
    ActivityPointsStatusColumn status = ActivityPointsStatusColumn.active,
  }) {
    return ActivityLocalDataSource(db: db, clock: clock).store(
      ActivityModel(
        id: id,
        name: 'Track',
        description: '',
        createdAt: startedAt,
        startedAt: startedAt,
        stoppedAt: null, // never ceased — simulates a killed process
        points: [
          ActivityPointModel(
            latitude: 48.85,
            longitude: 2.35,
            elevation: 0,
            time: lastFixAt ?? startedAt,
            status: status,
          ),
        ],
      ),
    );
  }

  group('start / stop', () {
    blocTest<RecordingBloc, RecordingState>(
      'start persists an in-progress activity and begins ticking',
      build: buildBloc,
      act: (bloc) => bloc.add(const StartRecording()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) async {
        expect(bloc.state.isRecording, isTrue);
        expect(bloc.state.isPaused, isFalse);
        expect(bloc.state.isStarting, isFalse);
        // Persisted with no stoppedAt, so a kill right now would be resumable.
        final ongoing = await repository().fetchOngoing();
        expect(ongoing, isNotNull);
        expect(ongoing!.stoppedAt, isNull);
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'a second start while one is running is a no-op (no orphan activity)',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const StartRecording());
      },
      wait: const Duration(milliseconds: 80),
      verify: (bloc) async {
        final summaries = await repository().fetchSummaries();
        expect(
          summaries.length,
          1,
          reason: 'a double Start must not leave a second, near-empty row',
        );
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'stop clears the activity and marks it ceased in storage',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const StopRecording());
      },
      wait: const Duration(milliseconds: 80),
      verify: (bloc) async {
        expect(bloc.state.isRecording, isFalse);
        expect(bloc.state.elapsedTime, Duration.zero);
        expect(await repository().fetchOngoing(), isNull);
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'a second stop is a silent no-op rather than an error',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const StopRecording());
        bloc.add(const StopRecording());
      },
      wait: const Duration(milliseconds: 80),
      verify: (bloc) => expect(bloc.state.error, isNull),
      errors: () => isEmpty,
    );
  });

  group('elapsed time and pause bookkeeping', () {
    blocTest<RecordingBloc, RecordingState>(
      'elapsed follows the clock while running',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        clock.advance(const Duration(minutes: 7));
        bloc.add(const TickElapsed());
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) =>
          expect(bloc.state.elapsedTime, const Duration(minutes: 7)),
    );

    blocTest<RecordingBloc, RecordingState>(
      'time spent paused is excluded from elapsed',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));

        clock.advance(const Duration(minutes: 5)); // 5 min running
        bloc.add(const PauseRecording());
        await Future<void>.delayed(const Duration(milliseconds: 10));

        clock.advance(const Duration(minutes: 30)); // 30 min paused
        bloc.add(const PauseRecording()); // resume
        await Future<void>.delayed(const Duration(milliseconds: 10));

        clock.advance(const Duration(minutes: 2)); // 2 min running
        bloc.add(const TickElapsed());
      },
      wait: const Duration(milliseconds: 80),
      verify: (bloc) {
        expect(bloc.state.isPaused, isFalse);
        expect(
          bloc.state.elapsedTime,
          const Duration(minutes: 7),
          reason: '5 + 2 running; the 30 min pause must not count',
        );
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'the tick does not move elapsed while paused',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        clock.advance(const Duration(minutes: 3));
        bloc.add(const TickElapsed());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const PauseRecording());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        clock.advance(const Duration(hours: 2));
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) => expect(
        bloc.state.elapsedTime,
        const Duration(minutes: 3),
        reason: 'frozen at the pause instant',
      ),
    );
  });

  group('resume after an OS kill', () {
    blocTest<RecordingBloc, RecordingState>(
      'an ongoing activity is rehydrated from storage',
      setUp: () => seedOngoing(
        id: 'ongoing1',
        startedAt: start,
        lastFixAt: start.add(const Duration(minutes: 5)),
      ),
      build: buildBloc,
      act: (bloc) {
        clock.advance(const Duration(minutes: 6));
        bloc.add(const ResumeOngoingRecording());
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) {
        expect(bloc.state.activity?.id, 'ongoing1');
        expect(bloc.state.isPaused, isFalse);
        // The run was notionally still going, so the dead gap counts as elapsed.
        expect(bloc.state.elapsedTime, const Duration(minutes: 6));
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'an activity killed while paused resumes paused, with elapsed frozen at '
      'the last fix rather than including the dead time',
      setUp: () => seedOngoing(
        id: 'paused1',
        startedAt: start,
        lastFixAt: start.add(const Duration(minutes: 4)),
        status: ActivityPointsStatusColumn.paused,
      ),
      build: buildBloc,
      act: (bloc) {
        clock.advance(const Duration(hours: 3));
        bloc.add(const ResumeOngoingRecording());
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) {
        expect(bloc.state.isPaused, isTrue);
        expect(
          bloc.state.elapsedTime,
          const Duration(minutes: 4),
          reason: 'the 3 h the process was dead must not become elapsed time',
        );
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'an activity whose last fix is older than the 12 h staleness window is '
      'auto-ceased, not resumed as a bogus multi-hour live run',
      setUp: () => seedOngoing(id: 'stale1', startedAt: start),
      build: buildBloc,
      act: (bloc) {
        clock.advance(const Duration(hours: 13));
        bloc.add(const ResumeOngoingRecording());
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) async {
        expect(bloc.state.activity, isNull);
        expect(
          await repository().fetchOngoing(),
          isNull,
          reason: 'auto-ceased, so it stops being "in progress" forever',
        );
      },
    );

    test(
      'just inside the staleness window it is still resumable — guards the '
      'boundary against an off-by-one that would silently kill live runs',
      () async {
        await seedOngoing(id: 'fresh1', startedAt: start);
        clock.advance(
          ActivityLocalDataSource.ongoingStaleAfter -
              const Duration(minutes: 1),
        );
        expect((await repository().fetchOngoing())?.id, 'fresh1');
      },
    );

    test(
      'the resumed pause state is read from the LAST recorded point, not from '
      'whichever point happens to share the maximum timestamp',
      () async {
        // SQLite truncates DateTime to whole seconds, so the +/-1us signalLost
        // boundary pair bracketing a GPS outage ties with the fix beside it.
        // Selecting the point by max(time) then returns the EARLIEST of the tie
        // — a signalLost boundary — and misreads the recording state. Here the
        // run was paused when the process died; picking the boundary instead
        // would resume it unpaused and count the dead time as active.
        final tied = start.add(const Duration(minutes: 4));
        await ActivityLocalDataSource(db: db, clock: clock).store(
          ActivityModel(
            id: 'tie1',
            name: 'Track',
            description: '',
            createdAt: start,
            startedAt: start,
            stoppedAt: null,
            points: [
              ActivityPointModel(
                latitude: 48.85,
                longitude: 2.35,
                elevation: 0,
                time: start,
                status: ActivityPointsStatusColumn.active,
              ),
              // Same second as the real last fix below.
              ActivityPointModel(
                latitude: 48.85,
                longitude: 2.35,
                elevation: 0,
                time: tied,
                status: ActivityPointsStatusColumn.signalLost,
              ),
              ActivityPointModel(
                latitude: 48.86,
                longitude: 2.36,
                elevation: 0,
                time: tied,
                status: ActivityPointsStatusColumn.paused,
              ),
            ],
          ),
        );

        final bloc = buildBloc();
        addTearDown(bloc.close);
        clock.advance(const Duration(hours: 2));
        bloc.add(const ResumeOngoingRecording());
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(bloc.state.isPaused, isTrue);
        expect(
          bloc.state.elapsedTime,
          const Duration(minutes: 4),
          reason: 'the 2 h the process was dead must stay out of elapsed',
        );
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'resuming when a recording is already live is a no-op',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final id = bloc.state.activity!.id;
        bloc.add(const ResumeOngoingRecording());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.activity!.id, id);
      },
      wait: const Duration(milliseconds: 60),
    );

    test('a cold-start resume is resolved before a queued new start', () async {
      final oldStart = start.subtract(const Duration(minutes: 1));
      await seedOngoing(
        id: 'ongoing-before-kill',
        startedAt: oldStart,
        lastFixAt: oldStart,
      );
      final local = ActivityLocalDataSource(db: db, clock: clock);
      final repo = _DelayedResumeRepository(local: local, clock: clock);
      final bloc = RecordingBloc(
        activities: repo,
        score: ScoreActivityUseCase(activities: repo, clock: clock),
        ensureBackgroundTracking: EnsureBackgroundTrackingUseCase(
          location: location,
        ),
        clock: clock,
      );
      addTearDown(bloc.close);
      addTearDown(() {
        if (!repo.release.isCompleted) repo.release.complete();
      });

      bloc.add(const ResumeOngoingRecording());
      await repo.entered.future;
      bloc.add(const StartRecording());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        await repository().fetchSummaries(),
        hasLength(1),
        reason: 'Start must remain queued while resume owns initialization',
      );

      repo.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(bloc.state.activity?.id, 'ongoing-before-kill');
      expect(await repository().fetchSummaries(), hasLength(1));
    });
  });

  group('scoring fixes', () {
    blocTest<RecordingBloc, RecordingState>(
      'a fix arriving with no recording running is dropped, not an error',
      build: buildBloc,
      act: (bloc) => bloc.add(ScoreFix(position: fixAt(start))),
      wait: const Duration(milliseconds: 40),
      verify: (bloc) => expect(bloc.state.error, isNull),
      errors: () => isEmpty,
    );

    blocTest<RecordingBloc, RecordingState>(
      'fixes are appended to the in-memory activity',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(
          ScoreFix(position: fixAt(start.add(const Duration(seconds: 5)))),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          ScoreFix(position: fixAt(start.add(const Duration(seconds: 10)))),
        );
      },
      wait: const Duration(milliseconds: 80),
      verify: (bloc) => expect(bloc.state.activity!.points.length, 2),
    );

    blocTest<RecordingBloc, RecordingState>(
      'live aggregates keep the activities list summary-only and current',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(
          ScoreFix(position: fixAt(start.add(const Duration(seconds: 5)))),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          ScoreFix(
            position: fixAt(
              start.add(const Duration(seconds: 10)),
              latitude: 48.851,
            ),
          ),
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) async {
        final summary = (await repository().fetchSummaries()).single;
        expect(summary.activeDistanceMeters, greaterThan(0));
        expect(summary.activeDuration, const Duration(seconds: 5));
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'a fix arriving after a long GPS outage is bracketed with signalLost '
      'boundary points so the gap leaves the active stats alone',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // Two fixes at the nominal 5 s cadence, then one 20 min later.
        bloc.add(
          ScoreFix(position: fixAt(start.add(const Duration(seconds: 5)))),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          ScoreFix(position: fixAt(start.add(const Duration(seconds: 10)))),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          ScoreFix(position: fixAt(start.add(const Duration(minutes: 20)))),
        );
      },
      wait: const Duration(milliseconds: 120),
      verify: (bloc) {
        final statuses = bloc.state.activity!.points
            .map((p) => p.status)
            .toList();
        expect(
          statuses
              .where((s) => s == ActivityPointStatusEntity.signalLost)
              .length,
          2,
          reason: 'one boundary point on each side of the outage',
        );
      },
    );

    blocTest<RecordingBloc, RecordingState>(
      'fixes recorded while paused are stored as paused',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const StartRecording());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const PauseRecording());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(
          ScoreFix(position: fixAt(start.add(const Duration(seconds: 5)))),
        );
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) => expect(
        bloc.state.activity!.points.last.status,
        ActivityPointStatusEntity.paused,
      ),
    );
  });

  group('tracking gap banner', () {
    blocTest<RecordingBloc, RecordingState>(
      'a reported gap is exposed then cleared',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const ReportTrackingGap(Duration(minutes: 4)));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.trackingGap, const Duration(minutes: 4));
        bloc.add(const ClearTrackingGap());
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) => expect(bloc.state.trackingGap, isNull),
    );
  });

  group('battery-optimisation exemption', () {
    blocTest<RecordingBloc, RecordingState>(
      'a denied exemption still starts the recording (FGS + wake lock remain)',
      build: () {
        location.batteryOptimizationDisabled = false;
        return buildBloc();
      },
      act: (bloc) => bloc.add(const StartRecording()),
      wait: const Duration(milliseconds: 60),
      verify: (bloc) {
        expect(location.batteryExemptionRequests, 1);
        expect(bloc.state.isRecording, isTrue);
      },
    );
  });
}

class _DelayedResumeRepository extends ActivityRepository {
  _DelayedResumeRepository({
    required ActivityLocalDataSource local,
    required Clock clock,
  }) : super(local: local, clock: clock);

  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ActivityEntity?> fetchOngoing() async {
    entered.complete();
    await release.future;
    return super.fetchOngoing();
  }
}
