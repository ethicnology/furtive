import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/repositories/activity_repository.dart';
import 'package:furtive/core/usecases/import_activity_from_gpx_use_case.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:furtive/features/activities/bloc/activities_state.dart';

import 'support/fakes.dart';

void main() {
  late LocalDatabase db;
  late FixedClock clock;
  final start = DateTime.utc(2026, 7, 26, 10);

  setUp(() {
    db = inMemoryDatabase();
    clock = FixedClock(start);
  });

  tearDown(() => db.close());

  ActivityRepository repository() => ActivityRepository(
    local: ActivityLocalDataSource(db: db, clock: clock),
    clock: clock,
  );

  ActivitiesBloc buildBloc({ImportActivityFromGpxUseCase? importGpx}) =>
      ActivitiesBloc(
        activities: repository(),
        // Always injected: the default would construct the real use case, which
        // reaches the locator for the app-wide database.
        importGpx:
            importGpx ?? ImportActivityFromGpxUseCase(activities: repository()),
      );

  Future<void> seed(String id, {int minutesAgo = 0}) {
    final startedAt = start.subtract(Duration(minutes: minutesAgo));
    return repository().store(
      ActivityEntity(
        id: id,
        name: 'Track',
        description: '',
        createdAt: startedAt,
        startedAt: startedAt,
        stoppedAt: startedAt.add(const Duration(minutes: 5)),
        points: const [],
      ),
    );
  }

  blocTest<ActivitiesBloc, ActivitiesState>(
    'fetch loads the list and clears the loading flag',
    setUp: () async {
      await seed('a1');
      await seed('a2', minutesAgo: 60);
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const FetchActivities()),
    wait: const Duration(milliseconds: 60),
    verify: (bloc) {
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, isNull);
      // Newest first.
      expect(bloc.state.activities!.map((a) => a.id), ['a1', 'a2']);
    },
  );

  test('fetch more makes activities beyond the first 50 reachable', () async {
    for (var i = 0; i < 55; i++) {
      await seed('a$i', minutesAgo: i);
    }
    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(const FetchActivities());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(bloc.state.activities, hasLength(kActivitiesPageSize));
    expect(bloc.state.hasMore, isTrue);

    bloc.add(const FetchMoreActivities());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(bloc.state.activities, hasLength(55));
    expect(bloc.state.hasMore, isFalse);
  });

  test('a fetch queued during import cannot finish the import early', () async {
    final imported = ActivityEntity(
      id: 'imported',
      name: 'Imported',
      description: '',
      createdAt: start,
      startedAt: start,
      stoppedAt: start.add(const Duration(minutes: 5)),
    );
    final delayed = _DelayedImport(repository(), imported);
    final bloc = buildBloc(importGpx: delayed);
    addTearDown(bloc.close);
    addTearDown(() {
      if (!delayed.release.isCompleted) delayed.release.complete();
    });

    bloc.add(const ImportActivityFromGpx(filePath: '/ignored.gpx'));
    await delayed.entered.future;
    bloc.add(const FetchActivities());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bloc.state.importStatus, ActivityImportStatus.inProgress);
    delayed.release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(bloc.state.importStatus, ActivityImportStatus.success);
    expect(bloc.state.activities!.map((a) => a.id), contains('imported'));
  });

  test(
    'a mutation completion reports failure without optimistic success',
    () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      final completion = Completer<void>();
      final failure = expectLater(completion.future, throwsA(isA<AppError>()));

      bloc.add(
        UpdateActivityName(
          activityId: 'missing',
          newName: 'Nope',
          completion: completion,
        ),
      );

      await failure;
      expect(
        bloc.state.error,
        isNull,
        reason: 'the awaiting page owns the error',
      );
    },
  );

  blocTest<ActivitiesBloc, ActivitiesState>(
    'rename updates the stored name and refreshes the list',
    setUp: () => seed('a1'),
    build: buildBloc,
    act: (bloc) => bloc.add(
      const UpdateActivityName(activityId: 'a1', newName: 'Evening ride'),
    ),
    wait: const Duration(milliseconds: 80),
    verify: (bloc) {
      expect(bloc.state.activities!.single.name, 'Evening ride');
      expect(bloc.state.isLoading, isFalse);
    },
  );

  blocTest<ActivitiesBloc, ActivitiesState>(
    'delete removes the activity and refreshes the list',
    setUp: () async {
      await seed('a1');
      await seed('a2', minutesAgo: 60);
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const DeleteActivity(activityId: 'a1')),
    wait: const Duration(milliseconds: 80),
    verify: (bloc) => expect(bloc.state.activities!.map((a) => a.id), ['a2']),
  );

  blocTest<ActivitiesBloc, ActivitiesState>(
    'renaming a missing activity surfaces an error and clears loading — a stuck '
    'spinner would leave the page unusable',
    build: buildBloc,
    act: (bloc) =>
        bloc.add(const UpdateActivityName(activityId: 'nope', newName: 'x')),
    wait: const Duration(milliseconds: 60),
    verify: (bloc) {
      expect(bloc.state.error, isNotNull);
      expect(bloc.state.isLoading, isFalse);
    },
  );

  blocTest<ActivitiesBloc, ActivitiesState>(
    'a failed GPX import keeps its AppError type so the page can show the real '
    'reason rather than a generic message',
    build: () => buildBloc(importGpx: _FailingImport(repository())),
    act: (bloc) =>
        bloc.add(const ImportActivityFromGpx(filePath: '/nonexistent.gpx')),
    wait: const Duration(milliseconds: 60),
    verify: (bloc) {
      expect(bloc.state.error, isA<GpxParseError>());
      expect(bloc.state.isLoading, isFalse);
    },
  );

  blocTest<ActivitiesBloc, ActivitiesState>(
    'a fetch clears a stale error so the list page does not re-show it',
    setUp: () => seed('a1'),
    build: buildBloc,
    act: (bloc) async {
      bloc.add(const UpdateActivityName(activityId: 'nope', newName: 'x'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(bloc.state.error, isNotNull);
      bloc.add(const FetchActivities());
    },
    wait: const Duration(milliseconds: 80),
    verify: (bloc) => expect(bloc.state.error, isNull),
  );
}

class _FailingImport extends ImportActivityFromGpxUseCase {
  _FailingImport(ActivityRepository activities) : super(activities: activities);

  @override
  Future<ActivityEntity> call(dynamic file) async {
    throw GpxParseError('boom');
  }
}

class _DelayedImport extends ImportActivityFromGpxUseCase {
  _DelayedImport(this.activities, this.activity)
    : super(activities: activities);

  final ActivityRepository activities;
  final ActivityEntity activity;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ActivityEntity> call(dynamic file) async {
    entered.complete();
    await release.future;
    await activities.store(activity);
    return activity;
  }
}
