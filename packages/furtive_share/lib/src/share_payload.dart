import 'package:nostr/nostr.dart';

import 'share_wire.dart';

/// Live positions. Ephemeral range (20000-29999), so relays are not expected to
/// store them at all — the trace does not accumulate anywhere we do not control.
///
/// The cost of that choice is an observer arriving mid-run to a blank map, which
/// is what [shareLastKnownKind] exists to fix.
const int shareLiveKind = 22222;

/// Recent-history snapshot. Addressable range (30000-39999): a relay keeps only
/// the latest bounded snapshot per `(kind, pubkey, d)`.
///
/// This is the one place the design deliberately leaves recent route data on a
/// relay, and it is the reason the same NIP-40 expiration is attached: hygiene,
/// not a guarantee — the NIP is explicit that relays may keep expired events.
///
/// Both numbers were checked against the **machine-readable registry of kinds**
/// (`nostr-protocol/registry-of-kinds`, schema.yaml), not the table in the NIPs
/// README — that table says outright it is not exhaustive, and an earlier draft
/// of this file used 21000, which the registry lists as Lightning Pub RPC. A
/// collision would put our ciphertext in front of clients that believe they know
/// what the kind means. The registry has open pull requests, so this is worth
/// re-checking before release.
const int shareLastKnownKind = 32222;

/// Tags every share event carries.
///
/// The `d` tag is the derived topic, so it identifies the share without
/// identifying anyone. `expiration` is NIP-40.
///
/// [now] is injected rather than read from the clock so the guard below is
/// testable, and because the app already threads a Clock everywhere for exactly
/// this reason.
List<List<String>> shareEventTags({
  required String topic,
  required DateTime expiresAt,
  required DateTime now,
}) {
  // An expiration already in the past is not a short share, it is a silent one:
  // relays SHOULD drop such events on publish, so every position would be
  // accepted by our own code and discarded by every relay, with nothing to see
  // on either side.
  if (!expiresAt.isAfter(now)) {
    throw ArgumentError.value(
      expiresAt.toIso8601String(),
      'expiresAt',
      'must be in the future',
    );
  }
  return [
    ['d', topic],
    Expiration.tag(expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000),
  ];
}

/// Encrypts one update for the observer.
///
/// NIP-44 v2 rather than anything of our own: it is audited (Cure53, December
/// 2023), it ships published test vectors, and it is already implemented in the
/// nostr package. The ECDH is between this share's ephemeral publisher key and
/// the recipient key derived from the link secret, so only a link holder can
/// read it. NIP-44 also authenticates the payload with an HMAC, so a relay
/// cannot alter a position undetected.
///
/// That HMAC does **not** replace validating the event signature. NIP-44 is
/// explicit that the outer NIP-01 signature authenticates the whole payload and
/// MUST be checked *before* decrypting — the MAC is computed before signing
/// precisely because the signature is assumed to be there. An earlier version of
/// this comment had the order backwards, which would have invited the relay
/// client to skip it.
Future<String> encryptShareUpdate({
  required ShareUpdate update,
  required String publisherSecretKey,
  required String recipientPublicKey,
}) => Nip44.encrypt(
  plaintext: update.encode(),
  senderSecretKey: publisherSecretKey,
  recipientPubkey: recipientPublicKey,
);

/// Decrypts an update received from a relay.
///
/// [publisherPublicKey] must be the key pinned in the link, never the `pubkey`
/// field of the received event: trusting the event's own author would let anyone
/// who saw the link publish positions that decrypt cleanly.
///
/// Throws [ShareFormatException] when the payload is not a v1 update. A failed
/// MAC surfaces as the nostr package's own exception — deliberately not
/// flattened into one type, because "someone tampered with this" and "this is
/// from a newer app version" deserve different handling upstream.
Future<ShareUpdate> decryptShareUpdate({
  required String payload,
  required String recipientSecretKey,
  required String publisherPublicKey,
}) async {
  final plaintext = await Nip44.decrypt(
    payload: payload,
    recipientSecretKey: recipientSecretKey,
    senderPubkey: publisherPublicKey,
  );
  return ShareUpdate.decode(plaintext);
}

Future<String> encryptShareSnapshot({
  required ShareSnapshot snapshot,
  required String publisherSecretKey,
  required String recipientPublicKey,
}) => Nip44.encrypt(
  plaintext: snapshot.encode(),
  senderSecretKey: publisherSecretKey,
  recipientPubkey: recipientPublicKey,
);

Future<ShareSnapshot> decryptShareSnapshot({
  required String payload,
  required String recipientSecretKey,
  required String publisherPublicKey,
}) async {
  final plaintext = await Nip44.decrypt(
    payload: payload,
    recipientSecretKey: recipientSecretKey,
    senderPubkey: publisherPublicKey,
  );
  return ShareSnapshot.decode(plaintext);
}
