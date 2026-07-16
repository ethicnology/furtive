import 'package:bloc_test/bloc_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/database/tables/activity_points_table.dart';
import 'package:furtive/core/datasources/activity_local_data_source.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/models/activity_model.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/bloc/map_state.dart';

/// Regression coverage for the P0 bug diagnosed in docs/AUDIT-2026-07.md §1: an
/// in-progress activity surviving an OS process kill must be rehydrated on
/// InitMap regardless of whether the GPS one-shot fix or the position stream
/// fail to open — both do fail here, unavoidably, since no platform channel
/// mocks are registered for the geolocator plugin in a plain `flutter_test`
/// environment. That "everything GPS-related throws" is exactly the
/// real-world failure mode this test exercises (cold GPS right after an
/// unlock — see docs/AUDIT-2026-07.md §1.1) — the resume must not depend on it
/// succeeding. Also exercises H3 (docs/REVIEW-2026-07-FULL-APP.md): InitMap
/// dispatched twice in quick succession must not throw or double-open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> seedOngoingActivity(String id, DateTime startedAt) {
    final ds = ActivityLocalDataSource();
    return ds.store(
      ActivityModel(
        id: id,
        name: 'Track',
        description: '',
        createdAt: startedAt,
        startedAt: startedAt,
        stoppedAt: null, // never ceased — simulates a killed process.
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
    'InitMap resumes an ongoing activity from storage even though the '
    'one-shot GPS fix and the position stream both fail to open (no '
    'platform channel available in a plain test environment)',
    setUp: () => seedOngoingActivity(
      'ongoing1',
      DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    ),
    build: MapBloc.new,
    act: (bloc) => bloc.add(const InitMap()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) {
      expect(bloc.state.activity?.id, 'ongoing1');
      // No uncaught error reached the state despite every GPS call failing.
      expect(bloc.state.loadingStatus, isNull);
    },
  );

  blocTest<MapBloc, MapState>(
    'a stale (12h+) ongoing activity is auto-ceased instead of resumed',
    setUp: () => seedOngoingActivity(
      'stale1',
      DateTime.now().toUtc().subtract(const Duration(hours: 13)),
    ),
    build: MapBloc.new,
    act: (bloc) => bloc.add(const InitMap()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) {
      expect(bloc.state.activity, isNull);
    },
  );

  blocTest<MapBloc, MapState>(
    'two InitMap events in quick succession do not throw or crash the bloc '
    '(regression guard for the double position-stream-open race, H3)',
    build: MapBloc.new,
    act: (bloc) {
      bloc.add(const InitMap());
      bloc.add(const InitMap());
    },
    wait: const Duration(milliseconds: 200),
    errors: () => isEmpty,
  );
}
