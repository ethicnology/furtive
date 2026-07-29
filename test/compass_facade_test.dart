import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/facades/compass_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platform support', () {
    test('is Android-only, and yields an empty stream elsewhere', () async {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        final compass = CompassFacade(platform: platform);
        expect(compass.isSupported, isFalse, reason: platform.name);
        expect(await compass.headings().toList(), isEmpty);
      }
      expect(
        CompassFacade(platform: TargetPlatform.android).isSupported,
        isTrue,
      );
    });

    test('updatePosition is a no-op off Android rather than an error', () async {
      final compass = CompassFacade(platform: TargetPlatform.iOS);
      await expectLater(
        compass.updatePosition(latitude: 45.5, longitude: -73.6),
        completes,
      );
    });
  });

  group('smoothing', () {
    /// Drives the facade through the real platform channel plumbing so the
    /// smoothing is exercised exactly as it runs in the app.
    Future<List<double>> headingsFrom(List<double> samples) async {
      const channel = EventChannel('test/compass');
      const codec = StandardMethodCodec();
      final binding = TestDefaultBinaryMessengerBinding.instance;

      binding.defaultBinaryMessenger.setMockMessageHandler(channel.name, (
        message,
      ) async {
        final call = codec.decodeMethodCall(message);
        if (call.method == 'listen') {
          for (final sample in samples) {
            await binding.defaultBinaryMessenger.handlePlatformMessage(
              channel.name,
              codec.encodeSuccessEnvelope(sample),
              (_) {},
            );
          }
        }
        return codec.encodeSuccessEnvelope(null);
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMessageHandler(
          channel.name,
          null,
        ),
      );

      final compass = CompassFacade(
        events: channel,
        platform: TargetPlatform.android,
      );
      return compass.headings().take(samples.length).toList();
    }

    test('a steady bearing is reported as itself', () async {
      final out = await headingsFrom(List.filled(12, 90));
      expect(out.last, closeTo(90, 0.5));
    });

    test('crossing north does not swing the arrow to the south', () async {
      // The failure this guards: averaging the angles directly makes the mean
      // of 359 and 1 equal 180 — exactly backwards. Smoothing the unit vector
      // instead has no discontinuity at the wrap point.
      final out = await headingsFrom([
        350, 355, 358, 359, 0, 1, 3, 5, 5, 5, 5, 5,
      ]);
      for (final heading in out) {
        final nearNorth = heading > 330 || heading < 30;
        expect(nearNorth, isTrue, reason: 'got $heading, expected near north');
      }
      expect(out.last, closeTo(5, 6));
    });

    test('output always stays within [0, 360)', () async {
      final out = await headingsFrom([
        0, 359, 180, 1, 270, 90, 359.9, 0.1, 45, 300,
      ]);
      for (final heading in out) {
        expect(heading, greaterThanOrEqualTo(0));
        expect(heading, lessThan(360));
      }
    });

    test('it lags a jump rather than snapping, which is the point of '
        'smoothing a noisy magnetometer', () async {
      final out = await headingsFrom([0, 90]);
      expect(out.first, closeTo(0, 0.5), reason: 'first sample seeds it');
      expect(
        out.last,
        greaterThan(0),
        reason: 'moves toward the new bearing...',
      );
      expect(out.last, lessThan(45), reason: '...without jumping to it');
    });
  });
}
