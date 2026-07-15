import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/utils/gps_quality_filter.dart';

import '../datasources/location_gps_data_source.dart';

/// Sentinel verticalAccuracy stamped on a fix whose altitude was missing
/// (NaN), so the elevation-gain smoothing in activity_entity.dart never
/// trusts the synthesized 0 m elevation. Comfortably above
/// _maxElevationVerticalAccuracyMeters (20 m) in activity_entity.dart.
const double kUntrustedElevationAccuracyMeters = 1000000.0;

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

  /// [onRawFix] fires for every fix that arrives from the platform and has
  /// finite coordinates — BEFORE GpsQualityFilter has a chance to reject it
  /// on accuracy/implied-speed grounds. MapBloc's stale-stream watchdog
  /// (EnsureTracking) needs this: it must tell "the foreground
  /// service/stream actually died" apart from "the stream is alive but
  /// every fix currently fails the quality gate" (urban canyon, tree cover,
  /// indoors). Stamping the watchdog's clock only from fixes that survive
  /// filtering — the previous behaviour — made every one of those perfectly
  /// normal outages look identical to a dead stream: the watchdog would
  /// then tear down and reopen a healthy foreground service and show the
  /// user a false "tracking gap" banner. See REVIEW-2026-07-FULL-APP.md M1.
  Stream<PositionEntity> getPositionStream({void Function()? onRawFix}) {
    // Drop any frames with non-finite lat/lon — they crash flutter_map's
    // LatLng constructor ("LatLng is not finite") and corrupt downstream
    // distance / interpolation maths (NaN poisons cumulativeMeters and
    // every km-milestone derived from it).
    final raw = remoteDataSource
        .getPositionStream()
        .map(_toEntity)
        .where((p) => p != null)
        .cast<PositionEntity>();
    final tapped = onRawFix == null
        ? raw
        : raw.map((p) {
            onRawFix();
            return p;
          });
    // GpsQualityFilter then gates fixes on horizontal accuracy and implied
    // speed — a fresh instance per call, since it tracks the last-accepted
    // fix and each call corresponds to one stream open (see
    // MapBloc._openPositionStream). NOT applied to getCurrentLocation(): a
    // one-shot fix has no history to compare against, and rejecting it would
    // just make "centre on me" fail more often for no benefit. See
    // AUDIT-2026-07.md §4.
    return GpsQualityFilter().apply(tapped);
  }

  /// Returns null when the underlying fix has NaN/Infinity coordinates so
  /// callers can drop it instead of poisoning the activity track.
  PositionEntity? _toEntity(Position position) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return null;
    }
    // Altitude can legitimately be NaN on devices/fixes that don't report it
    // (common for an intermittent 2D-only fix mid-recording, not just on
    // devices that never report altitude); coerce to 0 so the elevation
    // maths don't propagate NaN.
    final altitudeMissing = !position.altitude.isFinite;
    final elevation = altitudeMissing ? 0.0 : position.altitude;
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
      // A missing altitude forces the elevation above to a synthesized 0 m —
      // that value must never be trusted by the elevation-gain smoothing in
      // activity_entity.dart, whatever the platform separately reports for
      // altitudeAccuracy. Without this, a single intermittent 2D-only fix
      // mid-recording (verticalAccuracy sanitizes to null on such fixes, same
      // as legitimately unmeasured altitude) is treated as trusted, and a
      // synthesized 0 m sample against a real altitude of e.g. 1500 m
      // produces several hundred metres of fake elevation gain per dropout.
      // kUntrustedElevation is a sentinel comfortably above
      // _maxElevationVerticalAccuracyMeters (20 m) so the smoothing's trust
      // filter always rejects it.
      verticalAccuracy: altitudeMissing
          ? kUntrustedElevationAccuracyMeters
          : sanitizeAccuracy(position.altitudeAccuracy),
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
