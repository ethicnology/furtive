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
      activity.points.every(
        (p) => p.status == ActivityPointStatusEntity.active,
      ),
      isTrue,
    );
    expect(activity.activeDistanceMeters, closeTo(111.32, 2));
  });

  test('multi-segment import does not bridge the gap between segments', () async {
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

    // 2 (seg1) + 2 (signalLost gap brackets) + 3 (seg2) = 7.
    expect(activity.points.length, 7);
    // The gap is bracketed by two signalLost boundaries: a duplicate of
    // seg1's last point (lon 0.001) and one of seg2's first (lon 1.000).
    final lost = activity.points
        .where((p) => p.status == ActivityPointStatusEntity.signalLost)
        .toList();
    expect(lost.length, 2);
    expect(lost.first.position.longitude, closeTo(0.001, 1e-9));
    expect(lost.last.position.longitude, closeTo(1.000, 1e-9));

    // Active distance = seg1 (~111 m) + seg2's TWO active legs (~222 m) = ~333,
    // NOT the ~111 km jump across the discontinuity, and not under-counting
    // seg2's first leg.
    expect(activity.activeDistanceMeters, closeTo(333, 5));

    // The gap carries its own metrics: ~10 s of signal lost (minus the 2µs
    // taken by the brackets) and the ~111 km straight line as an informative
    // distance — neither leaks into the active stats.
    expect(activity.signalLostDuration.inSeconds, 9); // 10s - 2µs floors to 9
    expect(activity.signalLostDistanceMeters, closeTo(111195, 500));
    expect(activity.activeDuration, const Duration(seconds: 30));
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
    final lost = activity.points.where(
      (p) => p.status == ActivityPointStatusEntity.signalLost,
    );
    expect(lost.length, 2);
    expect(activity.activeDistanceMeters, closeTo(222.6, 5));
  });

  test('startedAt/stoppedAt use min/max over all points, not document order — '
      'a file with out-of-chronological-order <trk> blocks (e.g. concatenated '
      'recordings) must not report stoppedAt before startedAt', () async {
    final file = await writeGpx('''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="0" lon="1.000"><time>2026-01-01T01:00:00Z</time></trkpt>
    <trkpt lat="0" lon="1.001"><time>2026-01-01T01:00:10Z</time></trkpt>
  </trkseg></trk>
  <trk><trkseg>
    <trkpt lat="0" lon="0.000"><time>2026-01-01T00:00:00Z</time></trkpt>
    <trkpt lat="0" lon="0.001"><time>2026-01-01T00:00:10Z</time></trkpt>
  </trkseg></trk>
</gpx>''');

    final activity = await ImportActivityFromGpxUseCase()(file);
    expect(activity.startedAt, DateTime.parse('2026-01-01T00:00:00Z'));
    expect(activity.stoppedAt, DateTime.parse('2026-01-01T01:00:10Z'));
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
