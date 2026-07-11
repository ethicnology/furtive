import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  ActivityPointEntity pt(
    double lat,
    double lon, {
    double ele = 0,
    int sec = 0,
    ActivityPointStatusEntity status = ActivityPointStatusEntity.active,
    double? verticalAccuracy,
  }) => ActivityPointEntity(
    position: PositionEntity(
      latitude: lat,
      longitude: lon,
      elevation: ele,
      verticalAccuracy: verticalAccuracy,
    ),
    time: t0.add(Duration(seconds: sec)),
    status: status,
  );

  ActivityEntity act(List<ActivityPointEntity> points) => ActivityEntity(
    id: 'test',
    name: kDefaultActivityName,
    description: '',
    createdAt: t0,
    startedAt: t0,
    stoppedAt: null,
    points: points,
  );

  group('empty / degenerate activities', () {
    test('no points => zeroed stats, no segments/splits/milestones', () {
      final a = act([]);
      expect(a.activeDistanceMeters, 0);
      expect(a.activeDuration, Duration.zero);
      expect(a.activeElevationGain, 0);
      expect(a.segments, isEmpty);
      expect(a.kmSplits, isEmpty);
      expect(a.kmMilestones, isEmpty);
      expect(a.activePaceMinPerKm, '--:--');
    });

    test('single point => one segment, no distance', () {
      final a = act([pt(48.85, 2.35)]);
      expect(a.segments.length, 1);
      expect(a.activeDistanceMeters, 0);
      expect(a.kmSplits, isEmpty);
    });

    test('non-finite coordinates are filtered out', () {
      final a = act([
        pt(double.nan, 2.0),
        pt(48.0, 2.0, sec: 1),
        pt(48.0, 2.001, sec: 2),
      ]);
      // NaN point dropped; the two finite points form one segment.
      expect(a.segments.length, 1);
      expect(a.segments.first.points.length, 2);
    });
  });

  group('distance / duration / speed', () {
    test('two points: great-circle distance and elapsed active time', () {
      // 0.001 deg of longitude at the equator ~= 111.32 m.
      final a = act([pt(0, 0, sec: 0), pt(0, 0.001, sec: 10)]);
      expect(a.activeDistanceMeters, closeTo(111.32, 0.5));
      expect(a.activeDuration, const Duration(seconds: 10));
      expect(a.activeSpeedMps, closeTo(11.13, 0.1));
      expect(a.activeSpeedKmh, closeTo(40.1, 0.5));
    });

    test('paused points contribute to paused stats, not active', () {
      final a = act([
        pt(0, 0, sec: 0),
        pt(0, 0.001, sec: 10),
        pt(0, 0.002, sec: 20, status: ActivityPointStatusEntity.paused),
        pt(0, 0.003, sec: 30, status: ActivityPointStatusEntity.paused),
      ]);
      expect(a.activeDistanceMeters, closeTo(111.32, 0.5));
      expect(a.pausedDistanceMeters, closeTo(111.32, 0.5));
      expect(a.activeDuration, const Duration(seconds: 10));
      expect(a.pausedDuration, const Duration(seconds: 10));
    });
  });

  group('elevation gain (D+ only)', () {
    test('sums positive deltas, ignores descents', () {
      final a = act([
        pt(0, 0, ele: 0, sec: 0),
        pt(0, 0.0001, ele: 10, sec: 1),
        pt(0, 0.0002, ele: 5, sec: 2),
        pt(0, 0.0003, ele: 15, sec: 3),
      ]);
      // +10 (0->10), -5 ignored, +10 (5->15) = 20.
      expect(a.activeElevationGain, closeTo(20, 0.001));
    });

    test(
      'falls back to raw sum when no point carries verticalAccuracy '
      '(legacy recordings / no quality signal at all)',
      () {
        // Same shape as the test above, confirming the smoothed path never
        // engages just because it exists — it needs an explicit quality
        // signal on at least one point.
        final a = act([
          pt(0, 0, ele: 0, sec: 0),
          pt(0, 0.0001, ele: 10, sec: 1),
          pt(0, 0.0002, ele: 5, sec: 2),
          pt(0, 0.0003, ele: 15, sec: 3),
        ]);
        expect(a.activeElevationGain, closeTo(20, 0.001));
      },
    );

    test(
      'smooths + applies a hysteresis dead-band once verticalAccuracy is '
      'present, suppressing GPS noise on a flat route',
      () {
        // A "flat" route with ±3-4 m GPS altitude noise around 100 m. The
        // raw sum of positive deltas would be ~15 m of bogus D+; smoothing
        // (5-sample trailing average) then a 10 m dead-band collapses every
        // wobble to zero real gain.
        const elevations = [100, 103, 99, 102, 98, 101, 100, 104, 97, 100];
        final points = [
          for (var i = 0; i < elevations.length; i++)
            pt(
              0,
              0.0001 * i,
              ele: elevations[i].toDouble(),
              sec: i * 5,
              verticalAccuracy: 5,
            ),
        ];
        final a = act(points);
        expect(a.activeElevationGain, closeTo(0, 0.001));
      },
    );

    test(
      'smooths + applies a hysteresis dead-band to register a genuine climb',
      () {
        // A clean 55 m ramp (100 -> 155 in 5 m steps). Worked out by hand: a
        // 5-sample trailing moving average followed by a 10 m dead-band
        // yields exactly 40 m (it inherently lags behind the moving average
        // and drops the sub-threshold tail) — nowhere near the raw 55 m, but
        // nowhere near the ~0 the flat-route case above gets either.
        final points = [
          for (var i = 0; i < 12; i++)
            pt(
              0,
              0.0001 * i,
              ele: 100.0 + i * 5,
              sec: i * 5,
              verticalAccuracy: 5,
            ),
        ];
        final a = act(points);
        expect(a.activeElevationGain, closeTo(40, 0.001));
      },
    );

    test(
      'excludes a point whose verticalAccuracy exceeds the trust threshold '
      'instead of letting it corrupt the smoothed trace',
      () {
        final points = [
          for (var i = 0; i < 12; i++)
            pt(
              0,
              0.0001 * i,
              ele: 100.0 + i * 5,
              sec: i * 5,
              verticalAccuracy: 5,
            ),
          // A wild outlier fix with untrustworthy vertical accuracy, spliced
          // in between two ramp points. If it weren't excluded it would blow
          // up the moving average and the resulting gain.
          pt(0, 0.00027, ele: 500, sec: 27, verticalAccuracy: 999),
        ];
        final a = act(points);
        // Same 40 m as the clean-ramp case above — the outlier is dropped
        // before smoothing ever sees it, not merely capped.
        expect(a.activeElevationGain, closeTo(40, 0.001));
      },
    );
  });

  group('pace formatting', () {
    test('zero speed => --:--', () {
      final a = act([pt(0, 0, sec: 0), pt(0, 0, sec: 10)]);
      expect(a.activePaceMinPerKm, '--:--');
    });

    test('formats min:ss per km', () {
      // 1000 m in 300 s = 5:00 / km.
      final a = act([pt(0, 0, sec: 0), pt(0, 0.008983, sec: 300)]);
      expect(a.activeDistanceMeters, closeTo(1000, 5));
      expect(a.activePaceMinPerKm, matches(RegExp(r'^[45]:\d\d$')));
    });
  });

  group('km splits and milestones', () {
    test('one full split + trailing partial', () {
      // Two ~556 m legs => crosses 1 km once, ~113 m partial remains.
      final a = act([
        pt(0, 0, sec: 0),
        pt(0, 0.005, sec: 60),
        pt(0, 0.010, sec: 120),
      ]);
      final splits = a.kmSplits;
      expect(splits.length, 2);
      expect(splits[0].isPartial, isFalse);
      expect(splits[0].distanceMeters, 1000);
      expect(splits[1].isPartial, isTrue);
      expect(splits[1].distanceMeters, closeTo(113, 5));

      final ms = a.kmMilestones;
      expect(ms.length, 1);
      expect(ms.first.km, 1);
    });

    test('trailing fragment under 50 m is dropped', () {
      // Just over 1 km, only a few metres past => no partial split.
      final a = act([
        pt(0, 0, sec: 0),
        pt(0, 0.005, sec: 60),
        pt(0, 0.009, sec: 110),
      ]);
      final splits = a.kmSplits;
      expect(splits.length, 1);
      expect(splits.single.isPartial, isFalse);
    });
  });

  group('formatPace', () {
    test('formats m:ss', () {
      expect(formatPace(5.5), '5:30');
      expect(formatPace(4), '4:00');
      expect(formatPace(6.25), '6:15');
    });

    test('carries 60 rounded seconds into the minute (no 5:60)', () {
      expect(formatPace(5.999), '6:00');
      expect(formatPace(9.9999), '10:00');
    });
  });

  group('km split duration accounts for stationary legs', () {
    test('split durations sum to active duration despite a zero-distance leg', () {
      final a = act([
        pt(0, 0, sec: 0),
        pt(0, 0.005, sec: 60), // ~556 m
        pt(0, 0.005, sec: 90), // stationary 30 s, same spot
        pt(0, 0.010, sec: 150), // ~556 m
      ]);
      final splits = a.kmSplits;
      expect(splits, isNotEmpty);
      final total = splits.fold<Duration>(
        Duration.zero,
        (sum, s) => sum + s.duration,
      );
      // The 30 s stationary stretch must be counted; total split time equals
      // the activity's active duration (150 s).
      expect(total, a.activeDuration);
      expect(total, const Duration(seconds: 150));
    });
  });

  group('segment-boundary (GPX import) bridging guard', () {
    test('huge jump across a paused boundary is not counted as active', () {
      // Mirrors ImportActivityFromGpx: first point of the second group is
      // marked paused so the discontinuity is excluded from active distance.
      final a = act([
        pt(0, 0, sec: 0),
        pt(0, 0.001, sec: 10),
        // ~111 km jump — the boundary point of the next segment.
        pt(0, 1.0, sec: 20, status: ActivityPointStatusEntity.paused),
        pt(0, 1.001, sec: 30),
      ]);
      // Only the 111 m first leg counts; the 111 km jump is bridged across a
      // segment boundary and excluded.
      expect(a.activeDistanceMeters, closeTo(111.32, 1));
    });
  });
}
