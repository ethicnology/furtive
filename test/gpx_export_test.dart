import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/usecases/export_activity_to_gpx_use_case.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ExportActivityToGpxUseCase's constructor eagerly builds an
  // ActivityRepository -> ActivityLocalDataSource, which reads
  // getIt.get<LocalDatabase>() in a field initialiser even though
  // generateGpx() (unlike call()) never touches the DB.
  late LocalDatabase db;
  late ExportActivityToGpxUseCase useCase;
  setUp(() {
    db = LocalDatabase.forTesting(NativeDatabase.memory());
    if (getIt.isRegistered<LocalDatabase>()) {
      getIt.unregister<LocalDatabase>();
    }
    getIt.registerSingleton<LocalDatabase>(db);
    useCase = ExportActivityToGpxUseCase();
  });
  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  final t0 = DateTime.utc(2026, 1, 1, 12);

  ActivityPointEntity pt(
    double lat,
    double lon, {
    double ele = 0,
    int sec = 0,
  }) => ActivityPointEntity(
    position: PositionEntity(latitude: lat, longitude: lon, elevation: ele),
    time: t0.add(Duration(seconds: sec)),
    status: ActivityPointStatusEntity.active,
  );

  ActivityEntity act(
    List<ActivityPointEntity> points, {
    String name = 'Track',
    String description = '',
    ActivityTypeEntity activityType = ActivityTypeEntity.unknown,
  }) => ActivityEntity(
    id: 'test',
    name: name,
    description: description,
    createdAt: t0,
    startedAt: t0,
    stoppedAt: t0.add(const Duration(seconds: 60)),
    points: points,
    activityType: activityType,
  );

  group('numeric formatting', () {
    test('never emits scientific notation for tiny coordinates/elevation', () {
      // Within 1cm of the equator/prime meridian — double.toString would
      // render this as "1e-7" for lat/lon, invalid for xsd:decimal.
      final gpx = useCase.generateGpx(
        act([pt(1e-7, 1e-7, ele: 1e-8, sec: 0), pt(1e-7, 2e-7, sec: 10)]),
      );
      expect(gpx, isNot(contains('e-')));
      expect(gpx, isNot(contains('E-')));
      expect(gpx, contains('lat="0.0000001"'));
    });

    test('formats a normal coordinate with 7 decimal places', () {
      final gpx = useCase.generateGpx(
        act([pt(48.8566, 2.3522), pt(48.8567, 2.3523, sec: 10)]),
      );
      expect(gpx, contains('lat="48.8566000" lon="2.3522000"'));
    });
  });

  group('XML escaping', () {
    test('escapes predefined entities in name/description', () {
      final gpx = useCase.generateGpx(
        act(
          [pt(0, 0), pt(0, 0.001, sec: 10)],
          name: 'Tom & Jerry <run>',
          description: 'quote " apostrophe \'',
        ),
      );
      expect(gpx, contains('<name>Tom &amp; Jerry &lt;run&gt;</name>'));
      expect(gpx, contains('<desc>quote &quot; apostrophe &apos;</desc>'));
    });

    test('strips illegal XML control characters instead of leaving them '
        'raw (can arrive via a name copied from an imported GPX)', () {
      final gpx = useCase.generateGpx(
        act([pt(0, 0), pt(0, 0.001, sec: 10)], name: 'Bad\u0001Name\u0007'),
      );
      expect(gpx, contains('<name>BadName</name>'));
      expect(gpx, isNot(contains('\u0001')));
    });

    test('keeps tab/LF/CR (legal XML whitespace) untouched', () {
      final gpx = useCase.generateGpx(
        act([
          pt(0, 0),
          pt(0, 0.001, sec: 10),
        ], description: 'line1\nline2\ttab'),
      );
      expect(gpx, contains('line1\nline2\ttab'));
    });
  });

  test('writes the activity type on every track for a lossless import', () {
    final gpx = useCase.generateGpx(
      act([
        pt(0, 0),
        pt(0, 0.001, sec: 10),
      ], activityType: ActivityTypeEntity.bike),
    );
    expect(gpx, contains('<type>bike</type>'));
  });

  group('segment mapping', () {
    test(
      'one <trk>/<trkseg> per active segment; paused stretches excluded',
      () {
        final gpx = useCase.generateGpx(
          act([
            pt(0, 0, sec: 0),
            pt(0, 0.001, sec: 10),
            ActivityPointEntity(
              position: PositionEntity(
                latitude: 0,
                longitude: 0.002,
                elevation: 0,
              ),
              time: t0.add(const Duration(seconds: 20)),
              status: ActivityPointStatusEntity.paused,
            ),
            pt(0, 0.003, sec: 30),
            pt(0, 0.004, sec: 40),
          ]),
        );
        expect('<trk>'.allMatches(gpx).length, 2);
        expect('<trkpt'.allMatches(gpx).length, 4); // paused point excluded.
      },
    );
  });
}
