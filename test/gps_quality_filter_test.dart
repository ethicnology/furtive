import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/utils/gps_quality_filter.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  // Longitude degrees at the equator: 1 deg ~ 111.32 km, so 0.0001 ~ 11.1 m.
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

  final walking = MovementProfileEntity.slowGround.tuning;
  final running = MovementProfileEntity.running.tuning;
  final driving = MovementProfileEntity.road.tuning;

  Future<List<PositionEntity>> collect(Stream<PositionEntity> s) => s.toList();

  group('horizontal accuracy gate', () {
    test('accepts a fix at the profile tolerance and rejects one past it', () async {
      final filter = GpsQualityFilter(tuning: running);
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, accuracy: 35, sec: 0),
            pos(lat: 0, lon: 0.00001, accuracy: 36, sec: 5),
          ]),
        ),
      );
      expect(out.length, 1);
      expect(out.single.accuracy, 35);
    });

    test('tolerance follows the activity: a fix a runner rejects is fine for '
        'a car', () async {
      // A precise fix first: the cold-start allowance accepts the opening fix
      // whatever its accuracy, so the tolerance can only be observed once an
      // anchor exists.
      Future<int> acceptedAfterAnchor(MovementTuning tuning) async {
        final out = await collect(
          GpsQualityFilter(tuning: tuning).apply(
            Stream.fromIterable([
              pos(lat: 0, lon: 0, accuracy: 5, sec: 0),
              pos(lat: 0, lon: 0.00001, accuracy: 45, sec: 1),
            ]),
          ),
        );
        return out.length - 1; // discount the anchor
      }

      expect(
        await acceptedAfterAnchor(running),
        0,
        reason: '45 m > 35 m tolerance',
      );
      expect(
        await acceptedAfterAnchor(driving),
        1,
        reason: '45 m < 50 m tolerance',
      );
    });

    test('never rejects for a missing (null) accuracy — unknown is not '
        'penalised', () async {
      final filter = GpsQualityFilter(tuning: running);
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
      final filter = GpsQualityFilter(tuning: running);
      // ~50 m in 5 s => 10 m/s, under the running profile's 12.5 m/s ceiling.
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
      final filter = GpsQualityFilter(tuning: running);
      // ~1.1 km in 5 s => ~220 m/s: a multipath/urban-canyon jump.
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
        final filter = GpsQualityFilter(tuning: running);
        final out = await collect(
          filter.apply(
            Stream.fromIterable([
              pos(lat: 0, lon: 0, sec: 0),
              // Rejected teleport.
              pos(lat: 0, lon: 0.01, sec: 5),
              // ~22 m from the original anchor over 10 s — plausible, and must
              // be accepted even though it looks like a teleport relative to
              // the rejected fix.
              pos(lat: 0, lon: 0.0002, sec: 10),
            ]),
          ),
        );
        expect(out.length, 2);
        expect(out.last.longitude, 0.0002);
      },
    );

    test('reported accuracy is subtracted before judging speed, so two vague '
        'fixes of a stationary phone are not a teleport', () async {
      // ~22 m apart in 1 s = 22 m/s, far above walking's 6 m/s ceiling — but
      // both fixes claim +/-12 m, which explains the whole displacement.
      final filter = GpsQualityFilter(tuning: walking);
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, accuracy: 12, sec: 0),
            pos(lat: 0, lon: 0.0002, accuracy: 12, sec: 1),
          ]),
        ),
      );
      expect(out.length, 2);
    });

    test('the same displacement IS suspicious when neither fix reports an '
        'accuracy to explain it', () async {
      final filter = GpsQualityFilter(tuning: walking);
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, sec: 0),
            pos(lat: 0, lon: 0.0002, sec: 1),
          ]),
        ),
      );
      expect(out.length, 1);
    });

    test('never rejects when either fix is missing a timestamp', () async {
      final filter = GpsQualityFilter(tuning: running);
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

    test(
      'rejects an out-of-order/backlogged fix (dt <= 0) instead of moving '
      'the anchor backwards and splicing a spurious zig-zag into the trace',
      () async {
        final filter = GpsQualityFilter(tuning: running);
        final out = await collect(
          filter.apply(
            Stream.fromIterable([
              pos(lat: 0, lon: 0, sec: 10),
              pos(lat: 0, lon: 0.05, sec: 5),
              pos(lat: 0, lon: 0.0002, sec: 15),
            ]),
          ),
        );
        expect(out.length, 2);
        expect(out.first.longitude, 0);
        expect(out.last.longitude, 0.0002);
      },
    );

    test('rejects a duplicate-timestamp fix (dt == 0) rather than treating it '
        'as a new anchor', () async {
      final filter = GpsQualityFilter(tuning: running);
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, sec: 10),
            pos(lat: 0, lon: 0.05, sec: 10),
            pos(lat: 0, lon: 0.0002, sec: 15),
          ]),
        ),
      );
      expect(out.length, 2);
      expect(out.last.longitude, 0.0002);
    });
  });

  group('sustained speed above the ceiling', () {
    /// A steady 130 km/h (36.1 m/s): 36 m every second.
    List<PositionEntity> motorway({int fixes = 12}) => [
      for (var i = 0; i <= fixes; i++)
        pos(lat: 0, lon: 0.000325 * i, accuracy: 8, sec: i),
    ];

    test('a car on a motorway is recorded normally under the road profile', () async {
      final filter = GpsQualityFilter(tuning: driving);
      final out = await collect(
        filter.apply(Stream.fromIterable(motorway())),
      );
      // 36 m/s is nowhere near the road profile's 97 m/s ceiling, so nothing
      // is even suspicious. This is the regression that mattered: the single
      // 35 m/s ceiling this replaces rejected EVERY fix above 126 km/h.
      expect(out.length, 13);
    });

    test('even under a wildly wrong profile the stream never goes silent — it '
        're-anchors instead of dropping everything', () async {
      // Recording a drive as a walk: every fix is implausible. The old filter
      // dropped the entire trip, because a rejection did not move the anchor
      // and the implied speed therefore stayed above the ceiling forever.
      final filter = GpsQualityFilter(tuning: walking);
      final out = await collect(
        filter.apply(Stream.fromIterable(motorway())),
      );
      expect(
        out.length,
        greaterThan(1),
        reason: 'a degraded trace beats no trace at all',
      );
      // The anchor keeps advancing, so the accepted points span the journey
      // rather than piling up at its start.
      expect(out.last.longitude, greaterThan(out.first.longitude));
    });
  });

  group('vague fixes never starve the stream', () {
    test('the very first fix is accepted however vague it is', () async {
      // Cold start: the first fixes after a stream opens are the least accurate
      // the receiver will ever produce. Rejecting them leaves the app with no
      // position at all rather than an imprecise one, which is strictly worse —
      // a ±150 m fix still puts the map on the right block.
      final filter = GpsQualityFilter(tuning: running);
      final out = await collect(
        filter.apply(
          Stream.fromIterable([pos(lat: 0, lon: 0, accuracy: 150, sec: 0)]),
        ),
      );
      expect(out, hasLength(1));
    });

    test('a sustained bad-signal stretch degrades the cadence instead of '
        'freezing it', () async {
      // Observed on device: indoors the phone reported 67–150 m against a 60 m
      // tolerance, so every fix was dropped about once every two seconds and
      // the cursor never moved. The accuracy check was the only path with no
      // escape hatch, contradicting this class's own invariant.
      final filter = GpsQualityFilter(tuning: running);
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            // A good fix first, so the cold-start allowance is not what is
            // being measured here.
            pos(lat: 0, lon: 0, accuracy: 5, sec: 0),
            for (var i = 1; i <= 20; i++)
              pos(lat: 0, lon: 0.000001 * i, accuracy: 120, sec: i),
          ]),
        ),
      );

      expect(
        out.length,
        greaterThan(1),
        reason: 'the stream must not go silent',
      );
      expect(
        out.length,
        lessThan(10),
        reason: 'nor should it accept everything: vague fixes stay throttled',
      );
    });

    test('a vague fix still cannot smuggle in a teleport', () async {
      // The escape hatch must not become a bypass. A forced-through vague fix
      // is still speed-checked; its large accuracy widens the slack term, but
      // not without limit.
      final filter = GpsQualityFilter(tuning: running);
      final out = await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, accuracy: 5, sec: 0),
            for (var i = 1; i <= 6; i++)
              pos(lat: 0, lon: 0.000001 * i, accuracy: 120, sec: i),
            // Half a degree of longitude away, ~55 km in one second.
            pos(lat: 0, lon: 0.5, accuracy: 120, sec: 7),
          ]),
        ),
      );
      expect(
        out.map((p) => p.longitude),
        everyElement(lessThan(0.1)),
        reason: 'the jump is rejected even though vague fixes are being forced',
      );
    });
  });

  group('rejection reporting', () {
    test('reports why each fix was dropped', () async {
      final filter = GpsQualityFilter(tuning: running);
      final reasons = <GpsRejectionReason>[];
      filter.onRejected = (_, reason) => reasons.add(reason);

      await collect(
        filter.apply(
          Stream.fromIterable([
            pos(lat: 0, lon: 0, accuracy: 5, sec: 0),
            pos(lat: 0, lon: 0.00001, accuracy: 99, sec: 1),
            pos(lat: 0, lon: 0.01, sec: 2),
            // Same stamp as the still-current anchor (the two fixes above were
            // rejected, so it never moved off sec: 0).
            pos(lat: 0, lon: 0.00002, sec: 0),
          ]),
        ),
      );

      expect(reasons, [
        GpsRejectionReason.tooVague,
        GpsRejectionReason.implausibleSpeed,
        GpsRejectionReason.outOfOrder,
      ]);
    });

    test('accepted fixes are silent', () async {
      final filter = GpsQualityFilter(tuning: running);
      var calls = 0;
      filter.onRejected = (_, _) => calls++;
      await collect(
        filter.apply(Stream.fromIterable([pos(lat: 0, lon: 0, accuracy: 5)])),
      );
      expect(calls, 0);
    });
  });
}
