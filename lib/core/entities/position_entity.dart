
class PositionEntity {
  final double latitude;
  final double longitude;
  final double elevation;

  /// When the GPS fix was actually obtained (from the platform), used to
  /// timestamp recorded points. Null for synthesised positions (map search
  /// centre, interpolated milestones) that aren't recorded.
  final DateTime? time;

  /// Estimated horizontal accuracy of [latitude]/[longitude], in metres
  /// (radius of the 68% confidence circle, per the Android/iOS location
  /// APIs). Null when the platform/provider doesn't report it (e.g. a
  /// synthesised position, or an older recording predating this field —
  /// callers must treat null as "unknown", not "perfect fix"). Used to
  /// reject noisy fixes before they reach the recorded trace; see
  /// GpsQualityFilter.
  final double? accuracy;

  /// Estimated vertical accuracy of [elevation], in metres. Same caveats as
  /// [accuracy]. Vertical GPS noise is typically 1.5-2x the horizontal
  /// figure; used to keep unreliable altitude samples out of the elevation
  /// gain (D+) calculation. See ActivityStatisticsExtension.
  final double? verticalAccuracy;

  /// Ground speed reported by the platform, in m/s. Null when unavailable.
  /// Informational / used transiently by GpsQualityFilter's teleport check
  /// when present — the app does not otherwise display it.
  final double? speed;

  /// Course over ground in degrees clockwise from true north, or null when the
  /// platform did not report one.
  ///
  /// This is the direction of *travel*, not the direction the device is
  /// pointing — a phone carried sideways still reports the path it is moving
  /// along. Read it through [PositionEntityExtension.trustedHeading] rather
  /// than directly: a stationary receiver still emits a value, and it is
  /// meaningless.
  final double? heading;

  /// Estimated error on [heading], in degrees. Same "null means unknown"
  /// caveat as [accuracy]. Android only reports it from API 26.
  final double? headingAccuracy;

  PositionEntity({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    this.time,
    this.accuracy,
    this.verticalAccuracy,
    this.speed,
    this.heading,
    this.headingAccuracy,
  });
}

/// Ground speed below which [PositionEntityExtension.trustedHeading] refuses to
/// report a course.
///
/// Course over ground is derived from movement, so a receiver that is not
/// moving has nothing to derive it from — it keeps emitting the last bearing,
/// or a flat zero, which would peg an on-screen arrow to "due north" for
/// anyone standing still. 0.5 m/s (1.8 km/h) sits below a slow walk.
///
/// A starting value to validate on real recordings, not a measured constant.
const double kMinSpeedForHeadingMps = 0.5;

extension PositionEntityExtension on PositionEntity {
  /// [heading] when it can be believed, else null.
  ///
  /// Guards the two ways the platform lies about it: a bearing reported while
  /// standing still, and Android's habit of filling the field with 0.0 when no
  /// bearing is available at all (`Location.hasBearing()` is false but the
  /// getter still returns a number, and geolocator surfaces it as 0 —
  /// indistinguishable from a genuine due-north course).
  double? get trustedHeading {
    final value = heading;
    final groundSpeed = speed;
    if (value == null || !value.isFinite || value < 0 || value > 360) {
      return null;
    }
    if (groundSpeed == null || groundSpeed < kMinSpeedForHeadingMps) {
      return null;
    }
    return value;
  }
}
