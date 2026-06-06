import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:furtive/core/errors.dart';

// 0 = record every GPS fix. Used to be user-configurable but the setting
// confused more than it helped; the activity-recording use case wants the
// densest possible trace and the battery cost is acceptable for the
// foreground-service window.
const int _kDistanceFilterMeters = 0;

class LocationGpsDataSource {
  Future<Position> getCurrentLocation() async {
    final hasPermission = await checkLocationPermission();
    if (!hasPermission) {
      final granted = await requestLocationPermission();
      if (!granted) throw LocationPermissionError();
    }

    final position = await Geolocator.getCurrentPosition();
    return position;
  }

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(locationSettings: getLocationSettings());
  }

  Future<bool> requestLocationPermission() async {
    final permission = await Geolocator.requestPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<bool> checkLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  LocationSettings getLocationSettings() {
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _kDistanceFilterMeters,
        forceLocationManager: true,
        intervalDuration: const Duration(milliseconds: 5000),
        useMSLAltitude: true,
        // Foreground-service notification — required by Android FGS rules.
        // Shown silently in the "1 app active" row; most users won't read
        // it, which is why we keep the text generic in English rather than
        // localising it.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Tracking active',
          notificationText: 'Swipe to stop background tracking.',
          enableWakeLock: false,
          // setOngoing: false — user can swipe the notification away to
          // stop the foreground service. MapBloc listens for the resulting
          // stream-end and ceases the activity (see _onInitMap).
          setOngoing: false,
          // defType is the Android resource folder name, NOT the package id.
          // flutter_launcher_icons emits `launcher_icon.png` under mipmap-*.
          notificationIcon: AndroidResource(
            name: 'launcher_icon',
            defType: 'mipmap',
          ),
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: _kDistanceFilterMeters,
        // false — we run our own pause/resume. With true, iOS Core Location
        // auto-pauses updates when it thinks the user stopped (red light, rest
        // stop); the stream then goes silent with no onDone, and MapBloc's 90s
        // watchdog ceases the activity mid-run. Auto-pause is wrong for a
        // tracker that wants a continuous trace.
        pauseLocationUpdatesAutomatically: false,
        // Only set to true if our app will be started up in the background.
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _kDistanceFilterMeters,
      );
    }
    return locationSettings;
  }
}

class LocationPermissionError extends AppError {
  LocationPermissionError() : super('Location permission not granted');
}
