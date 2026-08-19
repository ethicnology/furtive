import 'dart:convert';
import 'dart:typed_data';

import 'package:nostr/nostr.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:pointycastle/key_derivators/hkdf.dart';

/// Everything an observer needs, derived from the 32 bytes in the link.
///
/// Nothing here is ever persisted. A share's keys live as long as the share,
/// are regenerated for the next one, and are recomputed from the link on the
/// viewer side. That is what makes "no identity" a structural property rather
/// than a policy: there is no long-term key material in this app to leak.
class ShareKeys {
  const ShareKeys({
    required this.recipientSecretKey,
    required this.recipientPublicKey,
    required this.topic,
  });

  /// Hex secp256k1 secret key the observer decrypts with. The publisher holds
  /// it too — it derives the same value — and uses the matching public key as
  /// the NIP-44 recipient.
  final String recipientSecretKey;

  /// Hex public key the publisher encrypts to.
  final String recipientPublicKey;

  /// Value of the `d` tag both sides address. Derived, so it discloses nothing:
  /// a relay operator sees an opaque 32 hex chars, not a user or a route.
  final String topic;
}

/// Argon2id cost when a share is password-protected: the OWASP Password Storage
/// Cheat Sheet's headline configuration, m=19456 KiB (19 MiB), t=2, p=1.
///
/// OWASP lists five configurations it considers equally strong, trading CPU
/// against RAM (46 MiB/t=1 through 7 MiB/t=5). This one is picked deliberately:
/// Argon2's work is roughly proportional to m×t, so 19×2 is the cheapest of the
/// five, and cheap matters because the viewer runs this in a browser where
/// pointycastle falls back to its register64 implementation (argon2.dart exports
/// argon2_register64_impl unless `dart.library.io`). Going below the OWASP
/// minimum is not on the table: a leaked link would become brute-forceable
/// offline, which is the only attack the password exists to stop.
///
/// Fixed by the v1 link format. Both sides must derive identical bytes, so these
/// are contract, not tuning knobs — changing one bumps the link version and
/// breaks every link already sent.
const int shareArgon2MemoryKib = 19456;
const int shareArgon2Iterations = 2;
const int shareArgon2Lanes = 1;

/// HKDF info labels. Domain-separated so the decryption key and the publicly
/// visible topic cannot be derived from one another: a relay knowing the topic
/// learns nothing about the key, which is the whole point of deriving both from
/// one secret instead of shipping two.
const String _recipientLabel = 'furtive-share-recipient-v1';
const String _topicLabel = 'furtive-share-topic-v1';

/// Order of the secp256k1 group. A derived scalar must land in [1, n-1] to be
/// a valid secret key.
final BigInt _secp256k1Order = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);

/// Derives the share keys from the link's 32-byte secret and, when the share is
/// password-protected, the password the observer typed.
///
/// The password is mixed in as the Argon2id *password* with the link secret as
/// *salt*, not concatenated into the HKDF input. That ordering is what makes a
/// leaked link survivable: an attacker holding the link must pay the Argon2id
/// cost per password guess, whereas a plain hash of (secret‖password) would be
/// a GPU-speed dictionary attack.
///
/// **This blocks the calling isolate**, by design, for as long as Argon2id takes
/// — far more than a frame budget when a password is set. The signature stays
/// synchronous rather than hiding that behind a Future, because the right way to
/// absorb it differs per platform and only the caller knows which it is: the app
/// offloads to `Isolate.run`, while the viewer has no isolates and must paint its
/// progress indicator and yield to the event loop *before* calling. A Future
/// here would let both callers believe the work was already off their thread.
ShareKeys deriveShareKeys({required Uint8List shareSecret, String? password}) {
  // ArgumentError, not ShareFormatException: this is our own call being wrong,
  // not a relay or a link handing us something malformed. The distinction is
  // load-bearing — one is a bug to fix, the other an expected condition to
  // surface to the user.
  if (shareSecret.length != 32) {
    throw ArgumentError.value(
      shareSecret.length,
      'shareSecret',
      'must be 32 bytes',
    );
  }
  if (password != null && password.isEmpty) {
    // An empty string is not "no password": it would silently derive different
    // keys from the unprotected case and produce an unreadable share.
    throw ArgumentError.value('', 'password', 'must not be empty');
  }

  final master = password == null
      ? shareSecret
      : _argon2id(password: password, salt: shareSecret);

  final secretKey = _deriveSecretKeyInCurveRange(master);
  final keys = Keys(secretKey);

  return ShareKeys(
    recipientSecretKey: keys.secret,
    recipientPublicKey: keys.public,
    topic: _hex(_hkdf(master, _topicLabel, 16)),
  );
}

Uint8List _argon2id({required String password, required Uint8List salt}) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: 32,
        iterations: shareArgon2Iterations,
        memory: shareArgon2MemoryKib,
        lanes: shareArgon2Lanes,
      ),
    );
  return generator.process(Uint8List.fromList(utf8.encode(password)));
}

/// HKDF-SHA256 output of [length] bytes for [label].
///
/// No salt: the input keying material is already 32 uniformly random bytes (or
/// an Argon2id output), so an extract salt adds nothing. The label is the info
/// parameter, which is what separates the two derived values.
Uint8List _hkdf(Uint8List ikm, String label, int length) {
  final derivator = HKDFKeyDerivator(SHA256Digest())
    ..init(
      HkdfParameters(ikm, length, null, Uint8List.fromList(utf8.encode(label))),
    );
  return derivator.process(Uint8List(0));
}

/// HKDF is a uniform random function, so its output can land outside the
/// secp256k1 group order — with probability around 2^-128, i.e. never in
/// practice. Handled anyway, and handled by *retrying with a counter* rather
/// than reducing modulo n, because a modular reduction would bias the key and
/// is the classic subtle mistake here. Deterministic on both sides.
String _deriveSecretKeyInCurveRange(Uint8List master) {
  for (var counter = 0; counter < 256; counter++) {
    final label = counter == 0 ? _recipientLabel : '$_recipientLabel-$counter';
    final candidate = _hkdf(master, label, 32);
    final scalar = BigInt.parse(_hex(candidate), radix: 16);
    if (scalar > BigInt.zero && scalar < _secp256k1Order) {
      return _hex(candidate);
    }
  }
  // Unreachable short of a broken HKDF; louder than returning a bad key.
  throw StateError('could not derive a share key inside the curve order');
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
