import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:furtive/core/logs.dart';

/// Device heading — which way the phone is pointing — as degrees clockwise
/// from **true** north.
///
/// Distinct from `PositionEntity.heading`, which is course over ground: the
/// direction you are *travelling*. A phone can point east while you walk north.
/// The map puck wants this one; distance and pace want the other.
///
/// Android only. The platform side ([CompassStreamHandler]) reads the fused
/// rotation vector, remaps it for screen rotation and corrects magnetic north
/// to true north. On every other platform this yields an empty stream, and
/// callers fall back to course over ground.
class CompassFacade {
  CompassFacade({
    EventChannel? events,
    MethodChannel? control,
    TargetPlatform? platform,
  }) : _events = events ?? const EventChannel('app.furtive/compass'),
       _control = control ?? const MethodChannel('app.furtive/compass_control'),
       _platform = platform ?? defaultTargetPlatform;

  final EventChannel _events;
  final MethodChannel _control;
  final TargetPlatform _platform;

  bool get isSupported => _platform == TargetPlatform.android;

  /// Smoothed heading in degrees [0, 360).
  ///
  /// Empty on unsupported platforms, and on Android devices with no rotation
  /// vector sensor (the platform sends a single null, which ends the stream
  /// rather than pretending north).
  Stream<double> headings() {
    if (!isSupported) return const Stream<double>.empty();
    final smoother = _HeadingSmoother();
    return _events
        .receiveBroadcastStream()
        .where((event) => event is double)
        .cast<double>()
        .map(smoother.add)
        .handleError((Object error, StackTrace trace) {
          logs.warning('compass stream', error: error, trace: trace);
        });
  }

  /// Tells the platform where we are, so it can convert magnetic north to true
  /// north. Cheap to call; declination changes over kilometres, not metres.
  Future<void> updatePosition({
    required double latitude,
    required double longitude,
    double altitude = 0,
  }) async {
    if (!isSupported) return;
    try {
      await _control.invokeMethod<void>('updatePosition', {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
      });
    } on PlatformException catch (e, s) {
      // A missing declination costs a few degrees of accuracy, not a working
      // compass — never worth failing a location update over.
      logs.warning('compass updatePosition', error: e, trace: s);
    } on MissingPluginException catch (e, s) {
      // The channel is not registered: an Android build without the native
      // side, or a host that reports itself as Android without implementing
      // it. Distinct from PlatformException, which is the *implementation*
      // refusing — and not caught by it, so without this clause the failure
      // escapes into the caller and takes a location update down with it.
      logs.warning('compass channel unavailable', error: e, trace: s);
    }
  }
}

/// Exponential smoothing of a bearing.
///
/// Averaging the angles directly is wrong at the wrap point: the mean of 359°
/// and 1° is 180°, i.e. exactly backwards, so a phone pointing north would
/// swing to south whenever the reading crossed zero. Smoothing the unit vector
/// and taking the angle of the result has no such discontinuity.
class _HeadingSmoother {
  static const double _alpha = 0.25;

  double? _x;
  double? _y;

  double add(double degrees) {
    final radians = degrees * math.pi / 180;
    final sampleX = math.cos(radians);
    final sampleY = math.sin(radians);

    final previousX = _x;
    final previousY = _y;
    final nextX = previousX == null
        ? sampleX
        : previousX + _alpha * (sampleX - previousX);
    final nextY = previousY == null
        ? sampleY
        : previousY + _alpha * (sampleY - previousY);
    _x = nextX;
    _y = nextY;

    final smoothed = math.atan2(nextY, nextX) * 180 / math.pi;
    return smoothed < 0 ? smoothed + 360 : smoothed;
  }
}
