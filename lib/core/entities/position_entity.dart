import 'package:latlong2/latlong.dart' show LatLng;

class PositionEntity {
  final double latitude;
  final double longitude;
  final double elevation;

  /// When the GPS fix was actually obtained (from the platform), used to
  /// timestamp recorded points. Null for synthesised positions (map search
  /// centre, interpolated milestones) that aren't recorded.
  final DateTime? time;

  PositionEntity({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    this.time,
  });
}

extension PositionEntityExtension on PositionEntity {
  LatLng toLatLng() => LatLng(latitude, longitude);
}
