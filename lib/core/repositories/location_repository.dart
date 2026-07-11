import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/utils/gps_quality_filter.dart';

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

  Stream<PositionEntity> getPositionStream() {
    // Drop any frames with non-finite lat/lon — they crash flutter_map's
    // LatLng constructor ("LatLng is not finite") and corrupt downstream
    // distance / interpolation maths (NaN poisons cumulativeMeters and
    // every km-milestone derived from it).
    //
    // GpsQualityFilter then gates fixes on horizontal accuracy and implied
    // speed — a fresh instance per call, since it tracks the last-accepted
    // fix and each call corresponds to one stream open (see
    // MapBloc._openPositionStream). NOT applied to getCurrentLocation(): a
    // one-shot fix has no history to compare against, and rejecting it would
    // just make "centre on me" fail more often for no benefit. See
    // AUDIT-2026-07.md §4.
    return GpsQualityFilter().apply(
      remoteDataSource
          .getPositionStream()
          .map(_toEntity)
          .where((p) => p != null)
          .cast<PositionEntity>(),
    );
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
    // Carry the platform fix time so recorded points are stamped when the fix
    // was taken, not when the bloc happens to process it. Matters when the OS
    // delivers a backlog of buffered fixes after the app resumes — stamping
    // them all with now() would collapse real elapsed time and corrupt
    // pace/splits. Guard against bogus epoch-0 timestamps some platforms emit.
    final ts = position.timestamp;
    final time = ts.isAfter(DateTime.utc(2000)) ? ts.toUtc() : null;
    // Quality metadata: carried through (not consumed here) so
    // GpsQualityFilter can gate the stream and the elevation-gain calculation
    // can weigh altitude by verticalAccuracy. Geolocator reports NaN/negative
    // sentinels on providers/platforms that don't supply a field — normalise
    // those to null rather than a bogus 0 or NaN so downstream code can tell
    // "unknown" apart from "reported and zero".
    double? sanitizeAccuracy(double v) => (v.isFinite && v >= 0) ? v : null;
    return PositionEntity(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: elevation,
      time: time,
      accuracy: sanitizeAccuracy(position.accuracy),
      verticalAccuracy: sanitizeAccuracy(position.altitudeAccuracy),
      speed: sanitizeAccuracy(position.speed),
    );
  }

  Future<bool> requestLocationPermission() async {
    return await remoteDataSource.requestLocationPermission();
  }

  Future<bool> checkLocationPermission() async {
    return await remoteDataSource.checkLocationPermission();
  }

  Future<bool> isBatteryOptimizationDisabled() async {
    return await remoteDataSource.isBatteryOptimizationDisabled();
  }

  Future<bool> requestDisableBatteryOptimization() async {
    return await remoteDataSource.requestDisableBatteryOptimization();
  }
}
