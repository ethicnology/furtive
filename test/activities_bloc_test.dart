import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/clock.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/entities/activity_entity.dart';
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
