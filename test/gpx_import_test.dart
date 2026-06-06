import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/locator.dart';
import 'package:furtive/core/usecases/import_activity_from_gpx_use_case.dart';

/// End-to-end test of ImportActivityFromGpxUseCase — exercises the real
/// parse → segment-stitch → persist path against an in-memory database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late Directory tmp;

  setUp(() async {
    db = LocalDatabase.forTesting(NativeDatabase.memory());
    if (getIt.isRegistered<LocalDatabase>()) {
      getIt.unregister<LocalDatabase>();
    }
    getIt.registerSingleton<LocalDatabase>(db);
    tmp = await Directory.systemTemp.createTemp('furtive_gpx_test');
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<File> writeGpx(String body) async {
    final f = File('${tmp.path}/test.gpx');
    await f.writeAsString(body);
    return f;
  }

  test('single-segment import marks every point active', () async {
    final file = await writeGpx('''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="0" lon="0"><time>2026-01-01T00:00:00Z</time></trkpt>
    <trkpt lat="0" lon="0.001"><time>2026-01-01T00:00:10Z</time></trkpt>
  </trkseg></trk>
</gpx>''');

    final activity = await ImportActivityFromGpxUseCase()(file);
    expect(activity.points.length, 2);
    expect(
      activity.points.every((p) => p.status == ActivityPointStatusEntity.active),
      isTrue,
    );
    expect(activity.activeDistanceMeters, closeTo(111.32, 2));
  });

  test('multi-segment import does not bridge the gap between segments',
      () async {
    // Two segments ~111 km apart. The straight-line jump between them must NOT
    // count as travelled distance (GPX <trkseg> = discontinuity).
    final file = await writeGpx('''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <trkseg>
      <trkpt lat="0" lon="0"><time>2026-01-01T00:00:00Z</time></trkpt>
      <trkpt lat="0" lon="0.001"><time>2026-01-01T00:00:10Z</time></trkpt>
    </trkseg>
    <trkseg>
      <trkpt lat="0" lon="1.000"><time>2026-01-01T00:00:20Z</time></trkpt>
      <trkpt lat="0" lon="1.001"><time>2026-01-01T00:00:30Z</time></trkpt>
      <trkpt lat="0" lon="1.002"><time>2026-01-01T00:00:40Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''');

    final activity = await ImportActivityFromGpxUseCase()(file);

    // 2 (seg1) + 1 (paused boundary) + 3 (seg2) = 6.
    expect(activity.points.length, 6);
    // Exactly one paused boundary, duplicating seg1's last point (lon 0.001).
    final paused = activity.points
        .where((p) => p.status == ActivityPointStatusEntity.paused)
        .toList();
    expect(paused.length, 1);
    expect(paused.single.position.longitude, closeTo(0.001, 1e-9));

    // Active distance = seg1 (~111 m) + seg2's TWO active legs (~222 m) = ~333,
    // NOT the ~111 km jump across the discontinuity, and not under-counting
    // seg2's first leg.
    expect(activity.activeDistanceMeters, closeTo(333, 5));
  });

  test('separate <trk> blocks are also treated as discontinuities', () async {
    final file = await writeGpx('''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="0" lon="0"><time>2026-01-01T00:00:00Z</time></trkpt>
    <trkpt lat="0" lon="0.001"><time>2026-01-01T00:00:10Z</time></trkpt>
  </trkseg></trk>
  <trk><trkseg>
    <trkpt lat="0" lon="2.000"><time>2026-01-01T00:00:20Z</time></trkpt>
    <trkpt lat="0" lon="2.001"><time>2026-01-01T00:00:30Z</time></trkpt>
  </trkseg></trk>
</gpx>''');

    final activity = await ImportActivityFromGpxUseCase()(file);
    final paused = activity.points
        .where((p) => p.status == ActivityPointStatusEntity.paused);
    expect(paused.length, 1);
    expect(activity.activeDistanceMeters, closeTo(222.6, 5));
  });

  test('a file with no track points is rejected', () async {
    final file = await writeGpx('''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>empty</name></metadata>
</gpx>''');
    expect(
      () => ImportActivityFromGpxUseCase()(file),
      throwsA(isA<GpxNoPointsError>()),
    );
  });
}
