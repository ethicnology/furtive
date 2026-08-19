import 'package:furtive_share/furtive_share.dart';
import 'package:test/test.dart';

/// The wire format is a contract with browser tabs already open and links
/// already pasted into conversations — neither can be migrated. These tests
/// exist to make a change to it deliberate rather than incidental.
void main() {
  final at = DateTime.utc(2026, 7, 30, 14, 25, 13);

  ShareUpdate update({
    double? elevation = 132.5,
    double? accuracy = 4.5,
    SharePointStatus status = SharePointStatus.active,
    bool finished = false,
  }) => ShareUpdate(
    position: SharePosition(
      time: at,
      latitude: 45.5019,
      longitude: -73.5674,
      status: status,
      elevation: elevation,
      accuracy: accuracy,
    ),
    startedAt: at.subtract(const Duration(minutes: 22, seconds: 9)),
    distanceMeters: 4231.75,
    elapsed: const Duration(minutes: 22, seconds: 9),
    finished: finished,
  );

  group('round trip', () {
    test('every field survives', () {
      final decoded = ShareUpdate.decode(update().encode());

      expect(decoded.position.time, at);
      expect(decoded.position.time.isUtc, isTrue);
      expect(decoded.position.latitude, 45.5019);
      expect(decoded.position.longitude, -73.5674);
      expect(decoded.position.elevation, 132.5);
      expect(decoded.position.accuracy, 4.5);
      expect(decoded.position.status, SharePointStatus.active);
      expect(
        decoded.startedAt,
        at.subtract(const Duration(minutes: 22, seconds: 9)),
      );
      expect(decoded.distanceMeters, 4231.75);
      expect(decoded.elapsed, const Duration(minutes: 22, seconds: 9));
    });

    test('omitted optionals stay omitted rather than becoming zero', () {
      final bare = update(elevation: null, accuracy: null);

      // Checked on the map rather than the JSON string: the status value is
      // itself "a", so a substring search would match it.
      expect(bare.position.toJson().containsKey('e'), isFalse);
      expect(bare.position.toJson().containsKey('a'), isFalse);
      final decoded = ShareUpdate.decode(bare.encode());
      expect(decoded.position.elevation, isNull);
      expect(
        decoded.position.accuracy,
        isNull,
        reason: 'unknown accuracy must not read as a perfect fix',
      );
    });

    test('every status crosses intact', () {
      for (final status in SharePointStatus.values) {
        expect(
          ShareUpdate.decode(update(status: status).encode()).position.status,
          status,
        );
      }
    });

    test('the end of a share crosses, and is absent until it happens', () {
      expect(ShareUpdate.decode(update().encode()).finished, isFalse);
      expect(
        ShareUpdate.decode(update(finished: true).encode()).finished,
        isTrue,
      );
      // Absent rather than false on the wire: an observer counting bytes must
      // not be able to tell the two apart before the padding is applied.
      expect(update().encode(), isNot(contains('"f"')));
      expect(update(finished: true).encode(), contains('"f":1'));
    });

    test('ending a share does not change the ciphertext length', () {
      expect(
        update(finished: true).encode().length,
        update().encode().length,
        reason: 'otherwise the last update announces itself by size alone',
      );
    });
  });

  group('outbound validation', () {
    test('refuses values the viewer would reject', () {
      final invalid = ShareUpdate(
        position: SharePosition(
          time: DateTime.utc(2026),
          latitude: double.nan,
          longitude: 2,
          status: SharePointStatus.active,
        ),
        startedAt: DateTime.utc(2026),
        distanceMeters: 0,
        elapsed: Duration.zero,
      );
      expect(() => invalid.encode(), throwsArgumentError);
    });

    test('a recent-history snapshot is fixed-size and round-trips', () {
      ShareUpdate atSecond(int second) => ShareUpdate(
        position: SharePosition(
          time: DateTime.utc(2026, 1, 1, 0, 0, second),
          latitude: 45 + second / 1000,
          longitude: -73,
          status: SharePointStatus.active,
        ),
        startedAt: DateTime.utc(2026, 1, 1),
        distanceMeters: second * 10,
        elapsed: Duration(seconds: second),
      );

      final short = ShareSnapshot([atSecond(1)]);
      final long = ShareSnapshot([
        for (var i = 1; i <= ShareSnapshot.maxUpdates; i++) atSecond(i),
      ]);
      expect(short.encode().length, long.encode().length);
      final decoded = ShareSnapshot.decode(long.encode());
      expect(decoded.updates, hasLength(ShareSnapshot.maxUpdates));
      expect(decoded.updates.last.distanceMeters, 600);
    });

    test('a snapshot cannot exceed its bounded history', () {
      final sample = update();
      expect(
        () => ShareSnapshot(List.filled(ShareSnapshot.maxUpdates + 1, sample)),
        throwsArgumentError,
      );
    });
  });

  group('the wire spelling is frozen', () {
    test('the status letters are what deployed viewers already parse', () {
      // A viewer is a browser tab already open and a link already sent. Renaming
      // an enum value must not change a letter on the wire; if this test has to
      // change, the link version has to change with it.
      expect(SharePointStatus.active.wire, 'a');
      expect(SharePointStatus.paused.wire, 'p');
      expect(SharePointStatus.signalLost.wire, 's');
      expect(
        SharePointStatus.values.map((s) => s.wire).toSet(),
        hasLength(SharePointStatus.values.length),
        reason: 'two statuses sharing a letter would silently alias',
      );
    });

    test('padding still applies at the worst case the bounds allow', () {
      // The leak comes back the moment a payload outgrows the padding target, and
      // it comes back silently. Measured worst case is 163 characters against a
      // 185-character budget, every optional present and the share ending; this
      // fails if a new field eats the remaining 22.
      final worst = ShareUpdate(
        position: SharePosition(
          time: DateTime.utc(2100),
          latitude: -89.1234567,
          longitude: -179.1234567,
          status: SharePointStatus.signalLost,
          elevation: -499.9999999,
          accuracy: 99999.9999999,
        ),
        startedAt: DateTime.utc(2026),
        distanceMeters: 40074999.99999,
        elapsed: const Duration(days: 30),
        finished: true,
      );

      expect(worst.encode().length, 192);
      expect(ShareUpdate.decode(worst.encode()).distanceMeters, 40074999.99999);
    });
  });

  group('a relay can return anything, so parsing refuses', () {
    test('not JSON', () {
      expect(
        () => ShareUpdate.decode('not json at all'),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a JSON array rather than an object', () {
      expect(
        () => ShareUpdate.decode('[1,2,3]'),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('an unknown version, rather than parsing it hopefully', () {
      expect(
        () => ShareUpdate.decode('{"v":2,"p":{},"d":0,"el":0}'),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('an unknown point status', () {
      final tampered = update().encode().replaceAll('"s":"a"', '"s":"z"');
      expect(
        () => ShareUpdate.decode(tampered),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a latitude outside the sphere', () {
      final tampered = update().encode().replaceAll('45.5019', '91.5');
      expect(
        () => ShareUpdate.decode(tampered),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a negative distance', () {
      final tampered = update().encode().replaceAll('4231.75', '-1');
      expect(
        () => ShareUpdate.decode(tampered),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a missing position object', () {
      expect(
        () => ShareUpdate.decode('{"v":1,"b":1,"d":0,"el":0}'),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a status that is not a string', () {
      expect(
        () => ShareUpdate.decode(
          '{"v":1,"p":{"t":1,"y":1,"x":1,"s":5},"b":1,"d":0,"el":0}',
        ),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('an infinite coordinate, which JSON can smuggle as 1e999', () {
      // Verified: jsonDecode('{"y":1e999}') yields Infinity. A non-finite
      // coordinate poisons MapLibre's camera and every later gesture throws, so
      // this has to die at the parse boundary rather than reach the viewer.
      expect(
        () => ShareUpdate.decode(
          '{"v":1,"p":{"t":1,"y":1e999,"x":1,"s":"a"},"b":1,"d":0,"el":0}',
        ),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a negative elapsed, which would render as a plausible pace', () {
      expect(
        () => ShareUpdate.decode(
          '{"v":1,"p":{"t":1,"y":1,"x":1,"s":"a"},"b":1,"d":100,"el":-3600}',
        ),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('an elapsed of 277 million hours', () {
      expect(
        () => ShareUpdate.decode(
          '{"v":1,"p":{"t":1,"y":1,"x":1,"s":"a"},"b":1,"d":100,"el":999999999999}',
        ),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a timestamp in the year 5138, which would pin itself to the end', () {
      // The observer sorts by time, so one such point outlives the session.
      expect(
        () => ShareUpdate.decode(
          '{"v":1,"p":{"t":99999999999999,"y":1,"x":1,"s":"a"},"b":1,"d":0,"el":0}',
        ),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a negative timestamp', () {
      expect(
        () => ShareUpdate.decode(
          '{"v":1,"p":{"t":-1,"y":1,"x":1,"s":"a"},"b":1,"d":0,"el":0}',
        ),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('the message never echoes the input, which may hold key material', () {
      // The app exports its logs, and a malformed link can be pasted anywhere.
      try {
        ShareUpdate.decode(
          '{"v":1,"p":{"y":"deadbeefsecret"},"b":1,"d":0,"el":0}',
        );
        fail('expected a ShareFormatException');
      } on ShareFormatException catch (e) {
        expect(e.message, isNot(contains('deadbeefsecret')));
      }
    });
  });

  group('the VM and the web must agree on what a JSON number is', () {
    test('an integral double is accepted where the VM would see an int', () {
      // dart2js has one number type: the viewer sees 60.0 where the phone sent
      // 60. A payload the publisher can produce must not be rejected by the
      // observer for reasons neither of them can see.
      final decoded = ShareUpdate.decode(
        '{"v":1,"p":{"t":1785421513000.0,"y":45.5,"x":-73.5,"s":"a"},'
        '"b":1785421453000.0,"d":100,"el":60.0}',
      );

      expect(decoded.elapsed, const Duration(seconds: 60));
      expect(decoded.position.time.millisecondsSinceEpoch, 1785421513000);
    });

    test(
      'a fractional value where an integer is required is still refused',
      () {
        expect(
          () => ShareUpdate.decode(
            '{"v":1,"p":{"t":1,"y":1,"x":1,"s":"a"},"b":1,"d":100,"el":60.5}',
          ),
          throwsA(isA<ShareFormatException>()),
        );
      },
    );
  });

  group('an unusable optional degrades instead of failing', () {
    test('a garbled elevation costs the elevation, not the position', () {
      final tampered = update().encode().replaceAll('132.5', '"garbage"');
      final decoded = ShareUpdate.decode(tampered);

      expect(decoded.position.elevation, isNull);
      expect(decoded.position.latitude, 45.5019);
    });

    test('an out-of-range optional is dropped, not carried', () {
      // 1e300 is finite, so a finiteness check alone let it through, and it
      // would wreck any chart axis it reached.
      for (final hostile in ['1e300', '-99999']) {
        final decoded = ShareUpdate.decode(
          '{"v":1,"p":{"t":1,"y":1,"x":1,"s":"a","e":$hostile},"b":1,"d":0,"el":0}',
        );
        expect(decoded.position.elevation, isNull, reason: hostile);
      }
    });

    test('a garbled end-of-share flag reads as still running', () {
      // Refusing here would cost the position over a field that only decorates
      // the badge. And a relay withholding the flag is no worse than a relay
      // dropping the whole event, which it can always do.
      for (final hostile in ['0', '"true"', 'null', '2', '[]']) {
        final decoded = ShareUpdate.decode(
          '{"v":1,"p":{"t":1,"y":1,"x":1,"s":"a"},"b":1,"d":0,"el":0,'
          '"f":$hostile}',
        );
        expect(decoded.finished, isFalse, reason: hostile);
        expect(decoded.position.latitude, 1, reason: hostile);
      }
    });

    test('a negative accuracy is dropped: it is not a radius', () {
      final decoded = ShareUpdate.decode(
        '{"v":1,"p":{"t":1,"y":1,"x":1,"s":"a","a":-50},"b":1,"d":0,"el":0}',
      );
      expect(decoded.position.accuracy, isNull);
    });

    test('a plausible elevation and accuracy still cross intact', () {
      final decoded = ShareUpdate.decode(
        '{"v":1,"p":{"t":1,"y":1,"x":1,"s":"a","e":-430,"a":12.5},'
        '"b":1,"d":0,"el":0}',
      );
      // The Dead Sea shore is below sea level, and aircraft cruise at 12 km.
      expect(decoded.position.elevation, -430);
      expect(decoded.position.accuracy, 12.5);
    });
  });
}
