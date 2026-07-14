import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/widgets/km_splits_chart.dart';

void main() {
  KmSplit split(int index, Duration duration) => KmSplit(
    index: index,
    distanceMeters: 1000,
    duration: duration,
    isPartial: false,
  );

  group('fastestAndSlowestSplitIndices', () {
    // km 1: 4:00/km (fast), km 2: 6:00/km (slow), km 3: 5:00/km (middle).
    final splits = [
      split(1, const Duration(minutes: 4)),
      split(2, const Duration(minutes: 6)),
      split(3, const Duration(minutes: 5)),
    ];

    test('pace mode: smaller value (less time/km) is fastest', () {
      final r = fastestAndSlowestSplitIndices(
        splits,
        (s) => s.paceMinPerKm,
        fasterIsSmaller: true,
      );
      expect(r.fastestIdx, 1);
      expect(r.slowestIdx, 2);
    });

    test('speed mode: LARGER value (more km/h) is fastest — regression guard '
        'for the pace/speed inversion bug (min speed used to be mislabelled '
        'fastest)', () {
      final r = fastestAndSlowestSplitIndices(
        splits,
        (s) => s.speedKmh,
        fasterIsSmaller: false,
      );
      // Same underlying reality as the pace case above — speed and pace
      // are inverses of each other, so the fastest/slowest km MUST be
      // identical regardless of which metric is displayed.
      expect(r.fastestIdx, 1);
      expect(r.slowestIdx, 2);
    });

    test('empty input yields no fastest/slowest', () {
      final r = fastestAndSlowestSplitIndices(
        [],
        (s) => s.paceMinPerKm,
        fasterIsSmaller: true,
      );
      expect(r.fastestIdx, isNull);
      expect(r.slowestIdx, isNull);
    });

    test('single split is both fastest and slowest', () {
      final r = fastestAndSlowestSplitIndices(
        [split(1, const Duration(minutes: 5))],
        (s) => s.paceMinPerKm,
        fasterIsSmaller: true,
      );
      expect(r.fastestIdx, 1);
      expect(r.slowestIdx, 1);
    });
  });
}
