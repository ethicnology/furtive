import 'dart:math' as math;

/// WGS84 equatorial radius, the same figure `Geolocator.distanceBetween` is
/// built on, so a circle produced here and a distance measured there agree.
const double _earthRadiusMeters = 6378137.0;

/// Vertices of a closed ring approximating a circle of [radiusMeters] around
/// ([latitude], [longitude]).
///
/// Exists because a GPS accuracy circle has to be expressed in **metres**, and
/// MapLibre's `CircleLayer` sizes its radius in **pixels** — a pixel radius is
/// correct at exactly one zoom level and lies at every other. Drawing the
/// circle as a real polygon lets the renderer scale it like any other
/// geometry.
///
/// The ring is closed (last vertex equals the first), which GeoJSON requires of
/// a polygon ring.
///
/// Returns an empty list for input that cannot describe a circle (non-finite
/// or non-positive radius, non-finite centre, fewer than three segments) so
/// callers can simply skip the layer.
///
/// Uses the equirectangular approximation: at accuracy-circle scale (metres to
/// a few hundred metres) the error against a proper geodesic is far below a
/// pixel. Near the poles the longitude scaling diverges, so those are refused
/// rather than drawn wrong. A circle spanning the antimeridian is not
/// normalised — it would need splitting into two polygons, which is not worth
/// the code for a case this app can only meet mid-Pacific.
List<({double latitude, double longitude})> geodesicCirclePoints({
  required double latitude,
  required double longitude,
  required double radiusMeters,
  int segments = 64,
}) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      !radiusMeters.isFinite ||
      radiusMeters <= 0 ||
      segments < 3) {
    return const [];
  }

  final cosLatitude = math.cos(latitude * math.pi / 180);
  // cos(lat) -> 0 at the poles makes the longitude offset explode.
  if (cosLatitude.abs() < 1e-6) return const [];

  final degreesPerMeterLat = 180 / (math.pi * _earthRadiusMeters);
  final deltaLatitude = radiusMeters * degreesPerMeterLat;
  final deltaLongitude = radiusMeters * degreesPerMeterLat / cosLatitude;

  return [
    for (var i = 0; i <= segments; i++)
      () {
        // i == segments repeats i == 0 exactly, closing the ring.
        final angle = 2 * math.pi * (i % segments) / segments;
        return (
          latitude: (latitude + deltaLatitude * math.cos(angle)).clamp(
            -90.0,
            90.0,
          ),
          longitude: longitude + deltaLongitude * math.sin(angle),
        );
      }(),
  ];
}
