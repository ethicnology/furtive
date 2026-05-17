import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/entities/position_entity.dart';

import '../datasources/location_gps_data_source.dart';

class LocationRepository {
  final remoteDataSource = LocationGpsDataSource();

  LocationRepository();

  Future<PositionEntity> getCurrentLocation() async {
    final position = await remoteDataSource.getCurrentLocation();
    return PositionEntity(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: position.altitude,
    );
  }

  Stream<PositionEntity> getPositionStream({required int accuracyInMeters}) {
    return remoteDataSource
        .getPositionStream(accuracyInMeters: accuracyInMeters)
        .map((position) {
          return PositionEntity(
            latitude: position.latitude,
            longitude: position.longitude,
            elevation: position.altitude,
          );
        });
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
