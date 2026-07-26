import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/datasources/location_gps_data_source.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/repositories/location_repository.dart';
import 'package:geolocator/geolocator.dart';

/// Coverage for the boundary where raw platform fixes become domain positions.
///
/// This is the app's GPS data-integrity gate and it was at 2.8%: every rule in
/// `_toEntity` exists because a specific class of bad fix corrupted a recording,
/// and none of them were verified. A single NaN reaching the trace poisons every
/// downstream distance and interpolation; a mis-sanitised altitude accuracy
/// fabricates hundreds of metres of elevation gain.
class _FakeGps implements LocationGpsDataSource {
  final StreamController<Position> raw = StreamController<Position>.broadcast();
  Position? current;
  bool batteryDisabled = true;
  bool permissionGranted = true;

  @override
  Stream<Position> getPositionStream() => raw.stream;

  @override
  Future<Position> getCurrentLocation() async {
    final c = current;
    if (c == null) throw StateError('no fix');
    return c;
  }

  @override
  Future<bool> checkLocationPermission() async => permissionGranted;

  @override
  Future<bool> requestLocationPermission() async => permissionGranted;

  @override
  Future<bool> isBatteryOptimizationDisabled() async => batteryDisabled;

  @override
  Future<bool> requestDisableBatteryOptimization() async => batteryDisabled;

  @override
  LocationSettings getLocationSettings({Duration? timeLimit}) =>
      const LocationSettings();

  Future<void> dispose() => raw.close();
}

Position rawFix({
  double latitude = 48.85,
  double longitude = 2.35,
  double altitude = 100,
  double accuracy = 5,
  double altitudeAccuracy = 3,
  double speed = 2,
  DateTime? timestamp,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: timestamp ?? DateTime.utc(2026, 7, 26, 10),
  accuracy: accuracy,
  altitude: altitude,
  altitudeAccuracy: altitudeAccuracy,
  heading: 0,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

void main() {
  late _FakeGps gps;
  late LocationRepository repository;

  setUp(() {
    gps = _FakeGps();
    repository = LocationRepository(gps: gps);
  });

  tearDown(() => gps.dispose());

  /// Pushes [fixes] through the stream and returns what survived.
  Future<List<PositionEntity>> emit(List<Position> fixes) async {
    final received = <PositionEntity>[];
    final sub = repository.getPositionStream().listen(received.add);
    for (final f in fixes) {
      gps.raw.add(f);
      await Future<void>.delayed(Duration.zero);
    }
    await sub.cancel();
    return received;
  }

  group('non-finite coordinates', () {
    test('a NaN latitude is dropped rather than reaching the trace', () async {
      final out = await emit([rawFix(latitude: double.nan)]);
      expect(out, isEmpty);
    });

    test('an infinite longitude is dropped', () async {
      final out = await emit([rawFix(longitude: double.infinity)]);
      expect(out, isEmpty);
    });

    test('a good fix either side of a bad one still gets through', () async {
      final out = await emit([
        rawFix(latitude: 48.0),
        rawFix(latitude: double.nan),
        rawFix(
          latitude: 48.001,
          timestamp: DateTime.utc(2026, 7, 26, 10, 0, 5),
        ),
      ]);
      expect(out.map((p) => p.latitude), [48.0, 48.001]);
    });

    test(
      'getCurrentLocation throws rather than returning a NaN position',
      () async {
        gps.current = rawFix(latitude: double.nan);
        await expectLater(repository.getCurrentLocation(), throwsStateError);
      },
    );
  });

  group('missing altitude', () {
    test(
      'a NaN altitude becomes 0 m but is flagged untrustworthy, so the '
      'elevation-gain smoothing cannot mistake it for a real sea-level sample',
      () async {
        final out = await emit([rawFix(altitude: double.nan)]);
        expect(out.single.elevation, 0);
        expect(
          out.single.verticalAccuracy,
          kUntrustedElevationAccuracyMeters,
          reason: 'must exceed the 20 m trust threshold in activity_entity',
        );
      },
    );

    test(
      'the untrusted sentinel wins even when the platform reports a good '
      'altitudeAccuracy for the very fix whose altitude is missing',
      () async {
        // The real-world shape: an intermittent 2D-only fix mid-recording. Left
        // trusted, a synthesized 0 m against a real 1500 m fabricates hundreds
        // of metres of gain per dropout.
        final out = await emit([
          rawFix(altitude: double.nan, altitudeAccuracy: 1),
        ]);
        expect(out.single.verticalAccuracy, kUntrustedElevationAccuracyMeters);
      },
    );

    test('a real altitude keeps the reported vertical accuracy', () async {
      final out = await emit([rawFix(altitude: 512, altitudeAccuracy: 4)]);
      expect(out.single.elevation, 512);
      expect(out.single.verticalAccuracy, 4);
    });
  });

  group('quality metadata sanitisation', () {
    test('NaN accuracy becomes null — "unknown", not "perfect"', () async {
      final out = await emit([rawFix(accuracy: double.nan)]);
      expect(out.single.accuracy, isNull);
    });

    test('a negative sentinel accuracy becomes null', () async {
      final out = await emit([rawFix(accuracy: -1)]);
      expect(out.single.accuracy, isNull);
    });

    test('zero is kept — reported and zero differs from unknown', () async {
      final out = await emit([rawFix(accuracy: 0)]);
      expect(out.single.accuracy, 0);
    });

    test('a negative speed becomes null', () async {
      final out = await emit([rawFix(speed: -1)]);
      expect(out.single.speed, isNull);
    });
  });

  group('fix timestamps', () {
    test('the platform fix time is carried through, in UTC', () async {
      final t = DateTime.utc(2026, 7, 26, 9, 30);
      final out = await emit([rawFix(timestamp: t)]);
      expect(out.single.time, t);
      expect(out.single.time!.isUtc, isTrue);
    });

    test(
      'a bogus epoch-0 timestamp becomes null rather than collapsing elapsed '
      'time to 56 years',
      () async {
        final out = await emit([
          rawFix(
            timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        ]);
        expect(out.single.time, isNull);
      },
    );

    test('a local-flagged timestamp is normalised to UTC', () async {
      final local = DateTime(2026, 7, 26, 12);
      final out = await emit([rawFix(timestamp: local)]);
      expect(out.single.time!.isUtc, isTrue);
      expect(out.single.time, local.toUtc());
    });
  });

  group('quality gate on the stream', () {
    test('a fix vaguer than 25 m is rejected', () async {
      final out = await emit([rawFix(accuracy: 30)]);
      expect(out, isEmpty);
    });

    test(
      'a teleport is rejected without moving the anchor, so the fix after it '
      'is still compared against the last known-good position',
      () async {
        final t0 = DateTime.utc(2026, 7, 26, 10);
        final out = await emit([
          rawFix(latitude: 48.0, timestamp: t0),
          // ~1 degree of latitude (111 km) in 5 s.
          rawFix(latitude: 49.0, timestamp: t0.add(const Duration(seconds: 5))),
          // Plausible walk from the FIRST fix, not from the rejected jump.
          rawFix(
            latitude: 48.0001,
            timestamp: t0.add(const Duration(seconds: 10)),
          ),
        ]);
        expect(out.map((p) => p.latitude), [48.0, 48.0001]);
      },
    );

    test('the one-shot fix is NOT quality-gated — a vague "centre on me" is '
        'better than none', () async {
      gps.current = rawFix(accuracy: 500);
      final position = await repository.getCurrentLocation();
      expect(position.accuracy, 500);
    });
  });

  group('raw-fix callback', () {
    test(
      'onRawFix fires for fixes the quality gate later rejects — otherwise a '
      'normal urban-canyon outage is indistinguishable from a dead stream',
      () async {
        var rawCount = 0;
        var accepted = 0;
        final sub = repository
            .getPositionStream(onRawFix: () => rawCount++)
            .listen((_) => accepted++);

        gps.raw.add(rawFix(accuracy: 5));
        await Future<void>.delayed(Duration.zero);
        gps.raw.add(rawFix(accuracy: 900)); // rejected by the gate
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(rawCount, 2, reason: 'both raw fixes seen');
        expect(accepted, 1, reason: 'only one survived the gate');
      },
    );

    test(
      'onRawFix does NOT fire for a non-finite frame — it never was a fix',
      () async {
        var rawCount = 0;
        final sub = repository
            .getPositionStream(onRawFix: () => rawCount++)
            .listen((_) {});
        gps.raw.add(rawFix(latitude: double.nan));
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(rawCount, 0);
      },
    );

    test('each stream open gets a fresh quality filter', () async {
      // The filter tracks the last accepted fix; sharing one across opens would
      // make the first fix after a reopen be speed-checked against a position
      // from before the gap.
      final t0 = DateTime.utc(2026, 7, 26, 10);
      final first = await emit([rawFix(latitude: 48.0, timestamp: t0)]);
      expect(first, hasLength(1));

      // Far away, but this is a fresh open so there is no anchor to jump from.
      final second = await emit([
        rawFix(latitude: 55.0, timestamp: t0.add(const Duration(seconds: 5))),
      ]);
      expect(second, hasLength(1));
    });
  });

  group('permission and battery pass-through', () {
    test('permission checks forward to the datasource', () async {
      gps.permissionGranted = false;
      expect(await repository.checkLocationPermission(), isFalse);
      expect(await repository.requestLocationPermission(), isFalse);
    });

    test('battery-optimisation checks forward to the datasource', () async {
      gps.batteryDisabled = false;
      expect(await repository.isBatteryOptimizationDisabled(), isFalse);
      expect(await repository.requestDisableBatteryOptimization(), isFalse);
    });
  });
}
