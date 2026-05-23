import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/entities/position_entity.dart';

import '../datasources/location_gps_data_source.dart';

class LocationRepository {
  final remoteDataSource = LocationGpsDataSource();

  LocationRepository();

  Future<PositionEntity> getCurrentLocation() async {
    final position = await remoteDataSource.getCurrentLocation();
    return _toEntity(position) ??
        (throw StateError(
          'Geolocator returned a position with non-finite coordinates',
        ));
  }

  Stream<PositionEntity> getPositionStream({
    String? notificationTitle,
    String? notificationBody,
  }) {
    // Drop any frames with non-finite lat/lon — they crash flutter_map's
    // LatLng constructor ("LatLng is not finite") and corrupt downstream
    // distance / interpolation maths (NaN poisons cumulativeMeters and
    // every km-milestone derived from it).
    return remoteDataSource
        .getPositionStream(
          notificationTitle: notificationTitle,
          notificationBody: notificationBody,
        )
        .map(_toEntity)
        .where((p) => p != null)
        .cast<PositionEntity>();
  }

  /// Returns null when the underlying fix has NaN/Infinity coordinates so
  /// callers can drop it instead of poisoning the activity track.
  PositionEntity? _toEntity(Position position) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return null;
    }
    // Altitude can legitimately be NaN on devices that don't report it;
    // coerce to 0 so the elevation maths don't propagate NaN.
    final elevation = position.altitude.isFinite ? position.altitude : 0.0;
    return PositionEntity(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: elevation,
    );
  }

  Stream<ServiceStatus> getServiceStatusStream() {
    return remoteDataSource.getServiceStatusStream();
  }

  Future<bool> requestLocationPermission() async {
    return await remoteDataSource.requestLocationPermission();
  }

  Future<bool> checkLocationPermission() async {
    return await remoteDataSource.checkLocationPermission();
  }

  Future<bool> isLocationServiceEnabled() async {
    return await remoteDataSource.isLocationServiceEnabled();
  }
}
