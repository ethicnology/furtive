import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/utils/geo_circle.dart';

void main() {
  // Measured with the same function the app uses for every other distance, so
  // the circle and the recorded track agree on what a metre is.
  double distanceFromCentre(
    double lat,
    double lon,
    ({double latitude, double longitude}) point,
  ) => Geolocator.distanceBetween(lat, lon, point.latitude, point.longitude);

  group('geometry', () {
    test('every vertex sits at the requested radius', () {
      const lat = 45.5;
      const lon = -73.6;
      const radius = 25.0;
      final ring = geodesicCirclePoints(
        latitude: lat,
        longitude: lon,
        radiusMeters: radius,
      );

      for (final point in ring) {
        expect(
          distanceFromCentre(lat, lon, point),
          closeTo(radius, radius * 0.01),
          reason: 'within 1% of $radius m',
        );
      }
    });

    test('holds at a high latitude, where longitude degrees shrink', () {
      // The failure mode this guards: scaling longitude by the same factor as
      // latitude produces an ellipse that gets worse the further from the
      // equator — invisible in Montreal, obvious in Tromsø.
      const lat = 69.65;
      const lon = 18.96;
      const radius = 60.0;
      final ring = geodesicCirclePoints(
        latitude: lat,
        longitude: lon,
        radiusMeters: radius,
      );

      for (final point in ring) {
        expect(
          distanceFromCentre(lat, lon, point),
          closeTo(radius, radius * 0.01),
        );
      }
    });

    test('holds at the equator', () {
      final ring = geodesicCirclePoints(
        latitude: 0,
        longitude: 0,
        radiusMeters: 100,
      );
      for (final point in ring) {
        expect(distanceFromCentre(0, 0, point), closeTo(100, 1));
      }
    });

    test('the ring is closed, as a GeoJSON polygon ring must be', () {
      final ring = geodesicCirclePoints(
        latitude: 45.5,
        longitude: -73.6,
        radiusMeters: 30,
        segments: 16,
      );
      expect(ring.length, 17, reason: 'segments + 1, the last repeating first');
      expect(ring.first.latitude, ring.last.latitude);
      expect(ring.first.longitude, ring.last.longitude);
    });

    test('radius scales the circle', () {
      const lat = 45.5;
      const lon = -73.6;
      final small = geodesicCirclePoints(
        latitude: lat,
        longitude: lon,
        radiusMeters: 10,
      );
      final large = geodesicCirclePoints(
        latitude: lat,
        longitude: lon,
        radiusMeters: 200,
      );
      expect(distanceFromCentre(lat, lon, small.first), closeTo(10, 1));
      expect(distanceFromCentre(lat, lon, large.first), closeTo(200, 5));
    });
  });

  group('degenerate input is refused rather than drawn wrong', () {
    test('a non-positive or non-finite radius yields no circle', () {
      for (final radius in [0.0, -5.0, double.nan, double.infinity]) {
        expect(
          geodesicCirclePoints(
            latitude: 45.5,
            longitude: -73.6,
            radiusMeters: radius,
          ),
          isEmpty,
          reason: 'radius $radius',
        );
      }
    });

    test('a non-finite centre yields no circle', () {
      expect(
        geodesicCirclePoints(
          latitude: double.nan,
          longitude: -73.6,
          radiusMeters: 10,
        ),
        isEmpty,
      );
      expect(
        geodesicCirclePoints(
          latitude: 45.5,
          longitude: double.infinity,
          radiusMeters: 10,
        ),
        isEmpty,
      );
    });

    test('the poles are refused, where the longitude scaling diverges', () {
      expect(
        geodesicCirclePoints(latitude: 90, longitude: 0, radiusMeters: 10),
        isEmpty,
      );
      expect(
        geodesicCirclePoints(latitude: -90, longitude: 0, radiusMeters: 10),
        isEmpty,
      );
    });

    test('fewer than three segments cannot describe a ring', () {
      expect(
        geodesicCirclePoints(
          latitude: 45.5,
          longitude: -73.6,
          radiusMeters: 10,
          segments: 2,
        ),
        isEmpty,
      );
    });
  });
}
