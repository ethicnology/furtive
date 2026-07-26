import 'dart:async';

import 'package:drift/native.dart';
import 'package:furtive/core/database/local_database.dart';
import 'package:furtive/core/datasources/location_gps_data_source.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/repositories/location_repository.dart';
import 'package:geolocator/geolocator.dart';

/// Hand-written fakes, deliberately not generated mocks.
///
/// The seams Phase 2 introduced are few and narrow (GPS, clock, database), so
/// explicit fakes read better than generated ones, need no build step, and never
/// silently stub a method the production code started depending on.

/// In-memory database, ready to hand to any datasource's `db:` parameter.
LocalDatabase inMemoryDatabase() =>
    LocalDatabase.forTesting(NativeDatabase.memory());

/// A [LocationRepository] whose fix stream and one-shot fix are fully driven by
/// the test. Overrides the repository rather than the datasource because the
/// repository is what consumers depend on, and its own logic (non-finite
/// filtering, GpsQualityFilter) is already covered by its own tests.
class FakeLocationRepository extends LocationRepository {
  FakeLocationRepository({
    this.currentLocation,
    this.failCurrentLocation = false,
  }) : super(gps: _UnusedGpsDataSource());

  /// Emit onto this to deliver fixes to whatever opened the stream.
  final StreamController<PositionEntity> fixes =
      StreamController<PositionEntity>.broadcast();

  /// Returned by [getCurrentLocation] unless [failCurrentLocation].
  PositionEntity? currentLocation;

  /// When true, [getCurrentLocation] throws — the real-world "GPS not warmed up
  /// right after an unlock" case that must not block a resume.
  bool failCurrentLocation;

  /// Set true to make [getPositionStream] throw, simulating a stream that can't
  /// be opened at all.
  bool failPositionStream = false;

  int positionStreamOpenCount = 0;
  int batteryExemptionRequests = 0;
  bool batteryOptimizationDisabled = true;

  @override
  Future<PositionEntity> getCurrentLocation() async {
    if (failCurrentLocation || currentLocation == null) {
      throw StateError('no fix available');
    }
    return currentLocation!;
  }

  @override
  Stream<PositionEntity> getPositionStream({void Function()? onRawFix}) {
    if (failPositionStream) throw StateError('cannot open stream');
    positionStreamOpenCount++;
    return fixes.stream.map((p) {
      onRawFix?.call();
      return p;
    });
  }

  @override
  Future<bool> isBatteryOptimizationDisabled() async =>
      batteryOptimizationDisabled;

  @override
  Future<bool> requestDisableBatteryOptimization() async {
    batteryExemptionRequests++;
    return batteryOptimizationDisabled;
  }

  Future<void> dispose() => fixes.close();
}

/// Never called: [FakeLocationRepository] overrides every method that would
/// reach the datasource. Exists only to satisfy the super constructor without
/// touching a real platform channel.
class _UnusedGpsDataSource implements LocationGpsDataSource {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('the fake repository should not reach the GPS');
}

/// Convenience builder for a position at a given time.
PositionEntity fixAt(
  DateTime time, {
  double latitude = 48.85,
  double longitude = 2.35,
  double elevation = 0,
  double? accuracy,
  double? verticalAccuracy,
}) => PositionEntity(
  latitude: latitude,
  longitude: longitude,
  elevation: elevation,
  time: time,
  accuracy: accuracy,
  verticalAccuracy: verticalAccuracy,
);

/// Unused import guard: keeps the geolocator import meaningful if a future fake
/// needs to build a raw [Position].
typedef RawPosition = Position;
