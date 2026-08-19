import 'dart:typed_data';

import 'package:furtive_share/furtive_share.dart';
import 'package:nostr/nostr.dart';
import 'package:test/test.dart';

void main() {
  final zeros = Uint8List(32);
  final counting = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  group('frozen vectors', () {
    // Generated from this implementation and then frozen. They are not
    // authoritative cryptography — they are a tripwire. The publisher runs on a
    // phone and the viewer in a browser, often on different app versions, and
    // both must derive the same bytes from the same link. A refactor that
    // changes any of these numbers breaks links that are already in people's
    // messages, so it has to be a decision, not a diff.
    test('no password', () {
      final keys = deriveShareKeys(shareSecret: zeros);

      expect(
        keys.recipientSecretKey,
        '5ef6d452feb707802efba35b576deeb8fbe2e97c366a9d270e488c39b2780765',
      );
      expect(
        keys.recipientPublicKey,
        '97ec2fd471e1e95b9048122900397ab5d49c24d94fc5eea9cdc062b215c8ae2d',
      );
      expect(keys.topic, 'fbbb190a88d52ce5cad873b17a829dfd');
    });

    test('a different secret, entirely different keys', () {
      final keys = deriveShareKeys(shareSecret: counting);

      expect(
        keys.recipientSecretKey,
        'f121113948e29ef36cf06b5d02ac8d33cfd2b230bd8c8895afca1a676b70e088',
      );
      expect(keys.topic, '0682e17abe6597dfa62acfea4ab68293');
    });

    test('with a password', () {
      final keys = deriveShareKeys(
        shareSecret: counting,
        password: 'correct horse',
      );

      expect(
        keys.recipientSecretKey,
        'c8d97412d3c5476fc7001f710528811c2f91f2cfd454fda0d48884d41efbb451',
      );
      expect(keys.topic, '2d240a4ca203946a83bf744f5a73f89d');
    });
  });

  group('shape', () {
    test('the derived key is a usable secp256k1 secret', () {
      final keys = deriveShareKeys(shareSecret: counting);

      expect(keys.recipientSecretKey, matches(RegExp(r'^[0-9a-f]{64}$')));
      // The real check: nostr accepts it and derives the same public key we
      // published in the link.
      expect(Keys(keys.recipientSecretKey).public, keys.recipientPublicKey);
    });

    test('the topic is 16 bytes of hex, and discloses nothing', () {
      final keys = deriveShareKeys(shareSecret: counting);

      expect(keys.topic, matches(RegExp(r'^[0-9a-f]{32}$')));
      // A relay operator sees the topic. It must not be a prefix or suffix of
      // anything secret — domain-separated HKDF labels are what guarantee that.
      expect(keys.recipientSecretKey, isNot(contains(keys.topic)));
      expect(keys.recipientPublicKey, isNot(contains(keys.topic)));
    });

    test(
      'deterministic: the viewer must land on the same keys as the phone',
      () {
        expect(
          deriveShareKeys(shareSecret: counting).recipientSecretKey,
          deriveShareKeys(shareSecret: counting).recipientSecretKey,
        );
      },
    );
  });

  group('the password is not decoration', () {
    test('it changes both the key and the topic', () {
      final without = deriveShareKeys(shareSecret: counting);
      final with_ = deriveShareKeys(
        shareSecret: counting,
        password: 'correct horse',
      );

      expect(with_.recipientSecretKey, isNot(without.recipientSecretKey));
      // The topic changing is what makes a wrong password indistinguishable
      // from an ended share: the viewer cannot even subscribe, so a leaked link
      // alone reveals no traffic at all.
      expect(with_.topic, isNot(without.topic));
    });

    test(
      'a wrong password derives an unrelated topic, not a failed decrypt',
      () {
        final right = deriveShareKeys(shareSecret: counting, password: 'right');
        final wrong = deriveShareKeys(shareSecret: counting, password: 'wrong');

        expect(wrong.topic, isNot(right.topic));
      },
    );

    test('an empty password is refused rather than treated as none', () {
      // Otherwise it derives the unprotected keys and produces a share nobody
      // can read, with no error anywhere.
      expect(
        () => deriveShareKeys(shareSecret: counting, password: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('preconditions are ArgumentError, not a format failure', () {
    // A relay handing us garbage is expected and must be surfaced to the user; a
    // wrong call from our own code is a bug. Collapsing both into one exception
    // type makes the second one look like the first, and it gets "handled".
    test('a secret of the wrong length', () {
      expect(
        () => deriveShareKeys(shareSecret: Uint8List(16)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the OWASP cost is what the contract says it is', () {
      // m=19456 KiB (19 MiB), t=2, p=1 — the OWASP Password Storage Cheat Sheet
      // configuration. Both sides must derive identical bytes, so a change here
      // invalidates every link already sent and has to bump the link version.
      expect(shareArgon2MemoryKib, 19456);
      expect(shareArgon2Iterations, 2);
      expect(shareArgon2Lanes, 1);
    });
  });
}
