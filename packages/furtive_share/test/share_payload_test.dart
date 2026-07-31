import 'dart:typed_data';

import 'package:furtive_share/furtive_share.dart';
import 'package:nostr/nostr.dart';
import 'package:test/test.dart';

void main() {
  final secret = Uint8List.fromList(List<int>.generate(32, (i) => i * 3 + 1));
  final at = DateTime.utc(2026, 7, 30, 15);

  final update = ShareUpdate(
    position: SharePosition(
      time: at,
      latitude: 45.5019,
      longitude: -73.5674,
      status: SharePointStatus.active,
      elevation: 42,
      accuracy: 6.5,
    ),
    startedAt: at.subtract(const Duration(minutes: 8)),
    distanceMeters: 1200,
    elapsed: const Duration(minutes: 8),
  );

  test('an observer holding the link reads the update', () async {
    // The publisher's key is ephemeral and per-share: generated here exactly as
    // the app will, and never stored anywhere.
    final publisher = Keys.generate();
    final derived = deriveShareKeys(shareSecret: secret);

    final payload = await encryptShareUpdate(
      update: update,
      publisherSecretKey: publisher.secret,
      recipientPublicKey: derived.recipientPublicKey,
    );

    final decoded = await decryptShareUpdate(
      payload: payload,
      recipientSecretKey: derived.recipientSecretKey,
      publisherPublicKey: publisher.public,
    );

    expect(decoded.position.latitude, 45.5019);
    expect(decoded.position.time, at);
    expect(decoded.distanceMeters, 1200);
    expect(decoded.elapsed, const Duration(minutes: 8));
  });

  test(
    'an observer holding the link reads a recent-history snapshot',
    () async {
      final publisher = Keys.generate();
      final derived = deriveShareKeys(shareSecret: secret);
      final payload = await encryptShareSnapshot(
        snapshot: ShareSnapshot([update]),
        publisherSecretKey: publisher.secret,
        recipientPublicKey: derived.recipientPublicKey,
      );

      final decoded = await decryptShareSnapshot(
        payload: payload,
        recipientSecretKey: derived.recipientSecretKey,
        publisherPublicKey: publisher.public,
      );
      expect(
        decoded.updates.single.position.latitude,
        update.position.latitude,
      );
    },
  );

  test('every update encrypts to the same length, whatever it says', () async {
    // Without fixed-length padding this leaked: measured 220 characters for a
    // fresh share and 260 a few kilometres in, because the numbers grow digits
    // and the optional fields come and go. A relay operator sees every
    // ciphertext, so that was enough to watch a share progress.
    final publisher = Keys.generate();
    final derived = deriveShareKeys(shareSecret: secret);

    Future<int> lengthOf(ShareUpdate u) async => (await encryptShareUpdate(
      update: u,
      publisherSecretKey: publisher.secret,
      recipientPublicKey: derived.recipientPublicKey,
    )).length;

    final fresh = ShareUpdate(
      position: SharePosition(
        time: at,
        latitude: 45.5,
        longitude: -73.5,
        status: SharePointStatus.active,
      ),
      startedAt: at,
      distanceMeters: 0,
      elapsed: Duration.zero,
    );
    final marathon = ShareUpdate(
      position: SharePosition(
        time: at,
        latitude: 45.5019123,
        longitude: -73.5674321,
        status: SharePointStatus.signalLost,
        elevation: 1132.5,
        accuracy: 4.5,
      ),
      startedAt: at.subtract(const Duration(hours: 4)),
      distanceMeters: 42195.75,
      elapsed: const Duration(hours: 4),
    );

    expect(await lengthOf(fresh), await lengthOf(marathon));
    expect(fresh.encode().length, marathon.encode().length);
  });

  test('padding survives the round trip and is ignored on the way in', () {
    final decoded = ShareUpdate.decode(update.encode());

    expect(decoded.distanceMeters, 1200);
    expect(decoded.position.latitude, 45.5019);
  });

  test('the relay sees ciphertext, not a position', () async {
    final publisher = Keys.generate();
    final derived = deriveShareKeys(shareSecret: secret);

    final payload = await encryptShareUpdate(
      update: update,
      publisherSecretKey: publisher.secret,
      recipientPublicKey: derived.recipientPublicKey,
    );

    expect(payload, isNot(contains('45.5')));
    expect(payload, isNot(contains('73.5')));
    // First base64 char encodes the top 6 bits of the version byte 0x02; the
    // rest of that char group comes from the random nonce, so only 'A' is
    // stable here.
    expect(payload, startsWith('A'), reason: 'NIP-44 v2 version byte');
  });

  test('someone without the link cannot read it', () async {
    final publisher = Keys.generate();
    final derived = deriveShareKeys(shareSecret: secret);
    final eavesdropper = deriveShareKeys(shareSecret: Uint8List(32));

    final payload = await encryptShareUpdate(
      update: update,
      publisherSecretKey: publisher.secret,
      recipientPublicKey: derived.recipientPublicKey,
    );

    await expectLater(
      decryptShareUpdate(
        payload: payload,
        recipientSecretKey: eavesdropper.recipientSecretKey,
        publisherPublicKey: publisher.public,
      ),
      throwsA(isA<CryptoException>()),
    );
  });

  test('a forged position from another key does not decrypt', () async {
    // Why the link pins the publisher's key: without it a viewer would trust
    // the event's own `pubkey`, and anyone who saw the link could publish
    // plausible positions on the same topic.
    final impostor = Keys.generate();
    final derived = deriveShareKeys(shareSecret: secret);
    final realPublisher = Keys.generate();

    final forged = await encryptShareUpdate(
      update: update,
      publisherSecretKey: impostor.secret,
      recipientPublicKey: derived.recipientPublicKey,
    );

    await expectLater(
      decryptShareUpdate(
        payload: forged,
        recipientSecretKey: derived.recipientSecretKey,
        publisherPublicKey: realPublisher.public,
      ),
      throwsA(isA<CryptoException>()),
    );
  });

  test('a tampered payload is refused, not silently mangled', () async {
    final publisher = Keys.generate();
    final derived = deriveShareKeys(shareSecret: secret);

    final payload = await encryptShareUpdate(
      update: update,
      publisherSecretKey: publisher.secret,
      recipientPublicKey: derived.recipientPublicKey,
    );
    // Flip a character in the middle of the ciphertext. NIP-44 authenticates
    // with an HMAC before decrypting, so this must fail loudly.
    final index = payload.length ~/ 2;
    final flipped = payload[index] == 'A' ? 'B' : 'A';
    final tampered = payload.replaceRange(index, index + 1, flipped);

    await expectLater(
      decryptShareUpdate(
        payload: tampered,
        recipientSecretKey: derived.recipientSecretKey,
        publisherPublicKey: publisher.public,
      ),
      throwsA(isA<CryptoException>()),
    );
  });

  group('event tags', () {
    test('carry the derived topic and a NIP-40 expiration', () {
      final tags = shareEventTags(
        topic: 'fbbb190a88d52ce5cad873b17a829dfd',
        expiresAt: DateTime.utc(2026, 7, 30, 16),
        now: DateTime.utc(2026, 7, 30, 15),
      );

      expect(tags, [
        ['d', 'fbbb190a88d52ce5cad873b17a829dfd'],
        ['expiration', '1785427200'],
      ]);
      expect(
        DateTime.fromMillisecondsSinceEpoch(1785427200 * 1000, isUtc: true),
        DateTime.utc(2026, 7, 30, 16),
      );
    });

    test('an expiration already past is refused, not published silently', () {
      // Relays SHOULD drop expired events on publish, so this would be accepted
      // by our code and discarded by every relay, with nothing visible anywhere.
      expect(
        () => shareEventTags(
          topic: 'fbbb190a88d52ce5cad873b17a829dfd',
          expiresAt: DateTime.utc(2026, 7, 30, 14),
          now: DateTime.utc(2026, 7, 30, 15),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the kind numbers are frozen and registry-checked', () {
      // Deployed viewers subscribe to these numbers, so a change breaks links
      // already sent — and the numbers must not collide with a registered kind,
      // or our ciphertext lands in front of a client that thinks it knows what
      // the kind means. 21000, used in an earlier draft, is Lightning Pub RPC.
      expect(shareLiveKind, 22222);
      expect(shareLastKnownKind, 32222);
    });

    test('the kinds stay in the ranges their semantics depend on', () {
      // Ephemeral: relays are not expected to store it. Addressable: only the
      // latest is kept. Move either out of range and the design changes meaning
      // without a single test failing elsewhere.
      expect(shareLiveKind, inInclusiveRange(20000, 29999));
      expect(shareLastKnownKind, inInclusiveRange(30000, 39999));
    });
  });
}
