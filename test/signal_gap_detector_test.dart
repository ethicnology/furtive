import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/utils/signal_gap_detector.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  group('threshold calibration', () {
    test('empty window falls back to the nominal interval (5s → 50s)', () {
      final d = SignalGapDetector();
      expect(d.threshold, const Duration(seconds: 50));
    });

    test('adapts to the observed cadence via the rolling median', () {
      final d = SignalGapDetector();
      // Degraded cadence: accepted fixes every 12 s (urban canyon, quality
      // filter dropping fixes). Threshold should widen to 10 × 12 = 120 s.
      var t = t0;
      for (var i = 0; i < 10; i++) {
        final next = t.add(const Duration(seconds: 12));
        expect(d.check(t, next), isNull);
        t = next;
      }
      expect(d.threshold, const Duration(seconds: 120));
    });

    test('median is insensitive to a single long interval', () {
      final d = SignalGapDetector();
      var t = t0;
      for (var i = 0; i < 9; i++) {
        final next = t.add(const Duration(seconds: 5));
        d.check(t, next);
        t = next;
      }
      // One 40 s interval (below threshold, so it IS recorded) barely moves
      // the median — the threshold stays at 10 × 5 s, not 10× the mean
      // (~85 s) a mean-based calibration would drift to.
      final next = t.add(const Duration(seconds: 40));
      expect(d.check(t, next), isNull);
      expect(d.threshold, const Duration(seconds: 50));
    });

    test('clamped to the 30s floor under a fast cadence', () {
      final d = SignalGapDetector();
      var t = t0;
      for (var i = 0; i < 5; i++) {
        final next = t.add(const Duration(seconds: 2));
        d.check(t, next);
        t = next;
      }
      // 10 × 2 s = 20 s < 30 s floor.
      expect(d.threshold, const Duration(seconds: 30));
    });

    test('clamped to the 6min ceiling under a very degraded cadence', () {
      final d = SignalGapDetector();
      var t = t0;
      for (var i = 0; i < 10; i++) {
        final next = t.add(const Duration(seconds: 45));
        d.check(t, next);
        t = next;
      }
      // 10 × 45 s = 450 s > 360 s ceiling.
      expect(d.threshold, const Duration(minutes: 6));
    });
  });

  group('gap detection', () {
    test('flags a gap beyond the threshold and returns its duration', () {
      final d = SignalGapDetector();
      final gap = d.check(t0, t0.add(const Duration(minutes: 23)));
      expect(gap, const Duration(minutes: 23));
    });

    test('does not flag normal cadence', () {
      final d = SignalGapDetector();
      expect(d.check(t0, t0.add(const Duration(seconds: 5))), isNull);
      expect(d.check(t0, t0.add(const Duration(seconds: 49))), isNull);
    });

    test('a detected gap does not inflate the cadence estimate', () {
      final d = SignalGapDetector();
      var t = t0;
      for (var i = 0; i < 10; i++) {
        final next = t.add(const Duration(seconds: 5));
        d.check(t, next);
        t = next;
      }
      final before = d.threshold;
      expect(d.check(t, t.add(const Duration(minutes: 23))), isNotNull);
      // The 23 min outage must not be averaged into the window: the very
      // next fix after recovery is judged against the same threshold.
      expect(d.threshold, before);
    });

    test('ignores non-positive intervals (clock skew, out-of-order fixes)', () {
      final d = SignalGapDetector();
      expect(d.check(t0, t0), isNull);
      expect(d.check(t0, t0.subtract(const Duration(seconds: 10))), isNull);
      expect(d.threshold, const Duration(seconds: 50));
    });

    test('reset clears the cadence history', () {
      final d = SignalGapDetector();
      var t = t0;
      for (var i = 0; i < 10; i++) {
        final next = t.add(const Duration(seconds: 12));
        d.check(t, next);
        t = next;
      }
      expect(d.threshold, const Duration(seconds: 120));
      d.reset();
      expect(d.threshold, const Duration(seconds: 50));
    });
  });
}
