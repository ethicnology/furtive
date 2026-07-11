import 'package:latlong2/latlong.dart' show LatLng;

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

  PositionEntity({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    this.time,
    this.accuracy,
    this.verticalAccuracy,
    this.speed,
  });
}

extension PositionEntityExtension on PositionEntity {
  LatLng toLatLng() => LatLng(latitude, longitude);
}
