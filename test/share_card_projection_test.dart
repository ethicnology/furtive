import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/widgets/share_card.dart';

void main() {
  const size = Size(1000, 1000); // square canvas keeps the math easy to read

  group('computeRouteProjection', () {
    test('a north-up route projects with y increasing downward', () {
      final p = computeRouteProjection(
        minLat: 0,
        maxLat: 1,
        minLon: 0,
        maxLon: 1,
        size: size,
      );
      // maxLat maps above (smaller y) than minLat.
      expect(p.project(1, 0).dy, lessThan(p.project(0, 0).dy));
      // East (larger lon) maps to the right (larger x).
      expect(p.project(0, 1).dx, greaterThan(p.project(0, 0).dx));
    });

    test('preserves aspect ratio at the equator (lon≈lat scale)', () {
      // At the equator cos(0)=1, so equal lat/lon spans → equal pixel spans.
      final p = computeRouteProjection(
        minLat: 0,
        maxLat: 1,
        minLon: 0,
        maxLon: 1,
        size: size,
      );
      final width = (p.project(0, 1).dx - p.project(0, 0).dx).abs();
      final height = (p.project(0, 0).dy - p.project(1, 0).dy).abs();
      expect(width, closeTo(height, 0.5));
    });

    test('applies cos(latitude) longitude correction away from equator', () {
      // A square-in-degrees box at 60°N covers ~half the east-west ground
      // distance of its north-south distance (cos 60° = 0.5), so it must
      // render about half as wide as it is tall.
      final p = computeRouteProjection(
        minLat: 60,
        maxLat: 61,
        minLon: 0,
        maxLon: 1,
        size: size,
      );
      final width = (p.project(60, 1).dx - p.project(60, 0).dx).abs();
      final height = (p.project(60, 0).dy - p.project(61, 0).dy).abs();
      expect(width / height, closeTo(math.cos(60.5 * math.pi / 180), 0.02));
      // And it must NOT be square (the bug this guards against).
      expect(width, lessThan(height * 0.8));
    });

    test('a wider-than-tall route fills the width, centred vertically', () {
      // 2° lon × 1° lat at the equator → ~2:1, fit by width on a square canvas.
      final p = computeRouteProjection(
        minLat: 0,
        maxLat: 1,
        minLon: 0,
        maxLon: 2,
        size: size,
      );
      final left = p.project(0, 0).dx;
      final right = p.project(0, 2).dx;
      // Spans nearly the full padded width (5% padding ⇒ ~900 px).
      expect((right - left), closeTo(900, 1));
    });

    test('degenerate single-point box does not divide by zero', () {
      final p = computeRouteProjection(
        minLat: 48.85,
        maxLat: 48.85,
        minLon: 2.35,
        maxLon: 2.35,
        size: size,
      );
      final o = p.project(48.85, 2.35);
      expect(o.dx.isFinite, isTrue);
      expect(o.dy.isFinite, isTrue);
    });
  });
}
