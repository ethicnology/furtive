import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/utils/gps_quality_filter.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  PositionEntity pos({
    required double lat,
    required double lon,
    double? accuracy,
    int sec = 0,
  }) => PositionEntity(
    latitude: lat,
    longitude: lon,
    elevation: 0,
    time: t0.add(Duration(seconds: sec)),
    accuracy: accuracy,
  );

  Future<List<PositionEntity>> collect(Stream<PositionEntity> s) => s.toList();

  group('horizontal accuracy gate', () {
    test('accepts fixes at or under the threshold', () async {
      final filter = GpsQualityFilter();
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, accuracy: 25, sec: 0),
            pos(lat: 0, lon: 0.00001, accuracy: 5, sec: 5),
          ]),
        ),
      );
      expect(out.length, 2);
    });

    test('rejects a fix vaguer than the threshold', () async {
      final filter = GpsQualityFilter();
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, accuracy: 5, sec: 0),
            pos(lat: 0, lon: 0.00001, accuracy: 26, sec: 5),
          ]),
        ),
      );
      expect(out.length, 1);
      expect(out.single.accuracy, 5);
    });

    test('never rejects for a missing (null) accuracy — unknown is not '
        'penalised', () async {
      final filter = GpsQualityFilter();
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, accuracy: null, sec: 0),
            pos(lat: 0, lon: 0.00001, accuracy: null, sec: 5),
          ]),
        ),
      );
      expect(out.length, 2);
    });
  });

  group('teleport / implied-speed gate', () {
    test('accepts a fix consistent with real, if fast, movement', () async {
      final filter = GpsQualityFilter();
      // ~50 m in 5 s => 10 m/s, well under the 35 m/s default cap.
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, sec: 0),
            pos(lat: 0, lon: 0.00045, sec: 5),
          ]),
        ),
      );
      expect(out.length, 2);
    });

    test('rejects a fix implying an impossible speed since the last '
        'accepted fix', () async {
      final filter = GpsQualityFilter();
      // ~1.1 km in 5 s => ~220 m/s: a multipath/urban-canyon jump, not real
      // human-powered movement.
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, sec: 0),
            pos(lat: 0, lon: 0.01, sec: 5),
          ]),
        ),
      );
      expect(out.length, 1);
      expect(out.single.longitude, 0);
    });

    test(
      'keeps comparing against the last good anchor, not the rejected '
      'outlier, so a real fix right after a jump is still accepted',
      () async {
        final filter = GpsQualityFilter();
        final out = await collect(
          filter.apply(
            Stream.fromIterable([
              pos(lat: 0, lon: 0, sec: 0),
              // Rejected teleport.
              pos(lat: 0, lon: 0.01, sec: 5),
              // Back near the original anchor — plausible movement from fix 1,
              // must be accepted even though it would look like a teleport
              // relative to the rejected fix.
              pos(lat: 0, lon: 0.0002, sec: 10),
            ]),
          ),
        );
        expect(out.length, 2);
        expect(out.last.longitude, 0.0002);
      },
    );

    test('never rejects when either fix is missing a timestamp', () async {
      final filter = GpsQualityFilter();
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            PositionEntity(latitude: 0, longitude: 0, elevation: 0),
            PositionEntity(latitude: 0, longitude: 1, elevation: 0),
          ]),
        ),
      );
      expect(out.length, 2);
    });
  });
}
