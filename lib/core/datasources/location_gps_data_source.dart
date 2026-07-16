import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:furtive/core/errors.dart';

// 0 = record every GPS fix. Used to be user-configurable but the setting
// confused more than it helped; the activity-recording use case wants the
// densest possible trace and the battery cost is acceptable for the
// foreground-service window.
const int _kDistanceFilterMeters = 0;

// Bound on the one-shot "get me a fix now" request (getCurrentLocation).
// Without this, a slow/cold GPS (typical right after an unlock) leaves the
// await pending forever — geolocator's own TimeoutException is only thrown
// when a timeLimit is actually configured. NOT applied to the continuous
// position stream (see getLocationSettings below): a long tunnel/indoor gap
// must not tear the stream down, only the single "centre on me" fix needs a
// deadline. See docs/AUDIT-2026-07.md §1.2 [P0-b].
const Duration _kCurrentLocationTimeLimit = Duration(seconds: 12);

class LocationGpsDataSource {
  Future<Position> getCurrentLocation() async {
    final hasPermission = await checkLocationPermission();
    if (!hasPermission) {
      final granted = await requestLocationPermission();
      if (!granted) throw LocationPermissionError();
    }

    // Pass the same settings as the stream — critically forceLocationManager
    // on Android. Without it, getCurrentPosition defaults to the fused
    // (Google Play Services) provider, which is ABSENT on this GMS-free FOSS
    // build's target devices (F-Droid / de-Googled), so the one-shot "centre
    // on me" fix would hang or fail. foregroundNotificationConfig is ignored
    // for a one-shot request. timeLimit bounds this one-shot call only
    // (throws TimeoutException past the deadline instead of hanging).
    final position = await Geolocator.getCurrentPosition(
      locationSettings: getLocationSettings(
        timeLimit: _kCurrentLocationTimeLimit,
      ),
    );
    return position;
  }

  Stream<Position> getPositionStream() {
    // No timeLimit here: geolocator throws a TimeoutException on the stream
    // itself once the deadline is passed without a fix, which would tear
    // down long-running tracking on a temporary GPS gap (tunnel, dense
    // urban canyon). Staleness while recording is instead detected and
    // recovered by MapBloc._onEnsureTracking.
    return Geolocator.getPositionStream(
      locationSettings: getLocationSettings(),
    );
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

  /// Whether the app is already exempt from battery optimisation (Doze / App
  /// Standby). Android-only; returns true on other platforms so callers treat
  /// them as "nothing to do". A false here is the single biggest predictor of
  /// the OS killing the foreground service while the phone is locked.
  Future<bool> isBatteryOptimizationDisabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  /// Ask the user to exempt the app from battery optimisation. Shows the
  /// system dialog (backed by REQUEST_IGNORE_BATTERY_OPTIMIZATIONS). No-op and
  /// returns true off Android. Returns whether the exemption is granted after
  /// the request. Best-effort: a denial is not fatal, tracking still relies on
  /// the FGS + wake lock, but the exemption makes a locked-screen kill far
  /// less likely on aggressive OEMs.
  Future<bool> requestDisableBatteryOptimization() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    if (await Permission.ignoreBatteryOptimizations.isGranted) return true;
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  LocationSettings getLocationSettings({Duration? timeLimit}) {
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _kDistanceFilterMeters,
        forceLocationManager: true,
        intervalDuration: const Duration(milliseconds: 5000),
        timeLimit: timeLimit,
        useMSLAltitude: true,
        // Foreground-service notification — required by Android FGS rules.
        // Shown silently in the "1 app active" row; most users won't read
        // it, which is why we keep the text generic in English rather than
        // localising it.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Recording activity',
          notificationText: 'Furtive is tracking your route.',
          // true — hold a partial wake lock so the CPU keeps delivering GPS
          // fixes once the screen is off and the device enters Doze. With it
          // false the OS suspends the process between Doze maintenance
          // windows, the position stream goes silent for minutes, and a
          // locked phone effectively stops recording. A continuous tracker
          // needs the wake lock for the foreground-service window.
          enableWakeLock: true,
          // true — make the notification non-dismissable. An ongoing FGS
          // notification is a far stronger signal to Android's task killer
          // (and aggressive OEM battery managers) to keep the process alive,
          // and it removes the accidental swipe-to-kill that silently ended
          // runs. Stopping is done in-app (pause → hold Stop), not by swipe.
          setOngoing: true,
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
        timeLimit: timeLimit,
        // false — we run our own pause/resume. With true, iOS Core Location
        // auto-pauses updates when it thinks the user stopped (red light, rest
        // stop); the stream then goes silent and the trace gets a long
        // unintended gap. Auto-pause is wrong for a tracker that wants a
        // continuous trace.
        pauseLocationUpdatesAutomatically: false,
        // Only set to true if our app will be started up in the background.
        showBackgroundLocationIndicator: true,
        // iOS only. On macOS the app has no background-location capability and
        // no NSLocationAlwaysAndWhenInUseUsageDescription, so requesting
        // background updates there makes Core Location refuse/log; macOS is
        // foreground-only.
        allowBackgroundLocationUpdates:
            defaultTargetPlatform == TargetPlatform.iOS,
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _kDistanceFilterMeters,
        timeLimit: timeLimit,
      );
    }
    return locationSettings;
  }
}

class LocationPermissionError extends AppError {
  LocationPermissionError() : super('Location permission not granted');
}
