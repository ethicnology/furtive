import 'dart:convert';
import 'dart:typed_data';

import 'share_wire.dart';

/// Relays used when a distributor does not provide `SHARE_RELAYS`.
const defaultShareRelayConfig = 'wss://nos.lol,wss://relay.primal.net';

/// The link handed to an observer, and its parser.
///
/// ```
/// https://<viewer-host>/#v1.<publisher-pubkey>.<share-secret>.<relays>
/// ```
///
/// Everything after the version is base64url without padding. The whole
/// descriptor lives in the **fragment**, which browsers neither send in the
/// request line nor put in `Referer` — that is the single property this format
/// is built around, and why nothing here may ever move into a query parameter.
///
/// Three things travel, and each earns its bytes:
///
///  * **the publisher's public key**, so the viewer can subscribe with
///    `authors` pinned to it. That turns nostr's signature layer into the
///    anti-injection mechanism: a forged position is not merely ignored, it is
///    never requested. Without pinning, anyone who saw the link could publish
///    plausible positions under the same topic.
///  * **the share secret**, from which the decryption key and the topic are
///    derived (see share_keys.dart).
///  * **the relay list**, because the sharer may have used their own relay. A
///    viewer defaulting to its own list would silently fail on self-hosted
///    shares, and shifting defaults would break links already sent. A link must
///    stay readable by someone whose viewer has never heard of that relay.
class ShareLink {
  /// Copies both the secret and the relay list rather than aliasing the caller's.
  ///
  /// This is a value type describing a share, and a caller that kept a reference
  /// to either could mutate a link after it was handed out — including the key
  /// bytes. Not const for that reason.
  ShareLink({
    required this.publisherPublicKey,
    required Uint8List shareSecret,
    required List<String> relays,
    this.passwordProtected = false,
  }) : _shareSecret = Uint8List.fromList(shareSecret),
       relays = List.unmodifiable(relays);

  /// Hex, 64 characters — the ephemeral key that signs this share's events.
  final String publisherPublicKey;

  /// 32 random bytes. Input to deriveShareKeys.
  final Uint8List _shareSecret;

  /// A defensive copy of the key material.
  ///
  /// [Uint8List] is mutable even when its field is final. Returning the stored
  /// buffer would let a caller change a descriptor after it had been shared.
  Uint8List get shareSecret => Uint8List.fromList(_shareSecret);

  /// Relay URLs, always `wss://`. Never empty, and unmodifiable.
  final List<String> relays;

  /// Whether the observer must type a password before anything can be derived.
  ///
  /// Announced rather than discovered. A viewer that had to guess would be
  /// unable to distinguish "needs a password" from "the share has ended", since
  /// a wrong master derives a different topic and therefore matches no events at
  /// all. The cost is that a link-thief learns a password exists — which they
  /// would discover on their first attempt regardless.
  final bool passwordProtected;

  static const String _versionPlain = 'v1';
  static const String _versionPassword = 'v1p';
  static const int maxRelays = 8;
  static const int maxRelayLength = 512;
  static const int maxFragmentLength = 8192;

  /// The fragment, without the leading `#`.
  ///
  /// Refuses to mint a link this class could not parse back. The asymmetry is
  /// worth guarding explicitly: a link with no relay encodes perfectly well and
  /// is unusable, so without this the app could hand out something it cannot
  /// itself read, and the failure would surface on the observer's screen.
  String toFragment() {
    if (relays.isEmpty) {
      throw ArgumentError.value(relays, 'relays', 'must list at least one');
    }
    if (relays.length > maxRelays) {
      throw ArgumentError.value(
        relays.length,
        'relays',
        'must list at most $maxRelays relays',
      );
    }
    final version = passwordProtected ? _versionPassword : _versionPlain;
    final fragment = [
      version,
      _encode(_bytesFromHex(publisherPublicKey)),
      _encode(_shareSecret),
      _encode(Uint8List.fromList(utf8.encode(relays.map(_host).join(',')))),
    ].join('.');
    if (fragment.length > maxFragmentLength) {
      throw ArgumentError.value(
        fragment.length,
        'relays',
        'encoded share link is too long',
      );
    }
    return fragment;
  }

  /// The full link. [viewerBase] is the viewer's origin, with or without a
  /// trailing slash.
  String toUri(String viewerBase) {
    final uri = Uri.tryParse(viewerBase);
    final localDevelopment =
        uri != null &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1');
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' &&
            !(localDevelopment && uri.scheme == 'http')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        viewerBase,
        'viewerBase',
        'must be a clean HTTPS URL (HTTP is allowed only on localhost)',
      );
    }
    final value = uri.toString();
    final base = value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
    return '$base/#${toFragment()}';
  }

  /// Parses a full link or a bare fragment.
  ///
  /// Refuses everything it does not fully understand. This input is untrusted by
  /// definition — it arrives from a browser address bar — and a partially
  /// understood link would produce a viewer that subscribes to the wrong topic
  /// and reports "nothing shared" instead of "this link is malformed".
  static ShareLink parse(String input) {
    var fragment = input;
    final hash = fragment.indexOf('#');
    if (hash >= 0) fragment = fragment.substring(hash + 1);
    if (fragment.isEmpty) {
      throw const ShareFormatException('link has no fragment');
    }
    if (fragment.length > maxFragmentLength) {
      throw const ShareFormatException('link fragment is too long');
    }

    final parts = fragment.split('.');
    if (parts.length != 4) {
      throw const ShareFormatException('link must have four segments');
    }

    final bool passwordProtected;
    switch (parts[0]) {
      case _versionPlain:
        passwordProtected = false;
      case _versionPassword:
        passwordProtected = true;
      default:
        throw const ShareFormatException('unsupported link version');
    }

    final publisher = _decode(parts[1], 'publisher key');
    if (publisher.length != 32) {
      throw const ShareFormatException('publisher key must be 32 bytes');
    }
    final secret = _decode(parts[2], 'share secret');
    if (secret.length != 32) {
      throw const ShareFormatException('share secret must be 32 bytes');
    }

    // utf8.decode throws a plain FormatException on invalid bytes, which would
    // sail straight past a caller catching ShareFormatException — the whole point
    // of having one type for "this input is malformed". A hand-edited link
    // reaches here, so it is not a theoretical path.
    final String hosts;
    try {
      hosts = utf8.decode(
        _decode(parts[3], 'relay list'),
        allowMalformed: false,
      );
    } on FormatException {
      throw const ShareFormatException('relay list is not valid UTF-8');
    }
    final relays = [
      for (final host in hosts.split(','))
        if (host.isNotEmpty) _relayUrl(host),
    ];
    if (relays.isEmpty) {
      throw const ShareFormatException('link lists no relay');
    }
    if (relays.length > maxRelays) {
      throw const ShareFormatException('link lists too many relays');
    }

    return ShareLink(
      publisherPublicKey: _hex(publisher),
      shareSecret: secret,
      relays: relays,
      passwordProtected: passwordProtected,
    );
  }

  /// Strips the scheme for the wire: `wss://` is implied, never encoded.
  static String _host(String relay) {
    final uri = Uri.tryParse(relay);
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(relay, 'relays', 'must contain only WSS URLs');
    }
    final host = relay.substring('wss://'.length);
    if (utf8.encode(host).length > maxRelayLength) {
      throw ArgumentError.value(relay, 'relays', 'relay URL is too long');
    }
    return host;
  }

  /// Rebuilds a relay URL, always as `wss://`.
  ///
  /// `ws://` is not merely discouraged, it is unrepresentable: a browser refuses
  /// a plaintext websocket from an https page as mixed content, so a `ws://`
  /// relay would produce a link that works on the phone and silently fails for
  /// every observer.
  static String _relayUrl(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      throw const ShareFormatException('empty relay host');
    }
    if (utf8.encode(trimmed).length > maxRelayLength) {
      throw const ShareFormatException('relay host is too long');
    }
    // A host with a scheme still in it means the encoder and this parser
    // disagree; better to refuse than to build `wss://wss://…`.
    if (trimmed.contains('://')) {
      throw const ShareFormatException('relay host must not carry a scheme');
    }
    // The viewer opens a websocket to whatever comes out of here, and the link
    // is fully attacker-controlled, so the host is validated rather than
    // interpolated hopefully. Whitespace, credentials, a query or a fragment all
    // mean this is not a bare host: `user:pass@`, `?`, `#` and a stray backslash
    // are exactly how a crafted link would try to reach somewhere else.
    if (RegExp(r'[\s?#\\@]').hasMatch(trimmed)) {
      throw const ShareFormatException('malformed relay host');
    }
    final uri = Uri.tryParse('wss://$trimmed');
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ShareFormatException('malformed relay host');
    }
    return 'wss://$trimmed';
  }

  static String _encode(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _decode(String value, String what) {
    // base64Url.decode insists on padding; the link deliberately omits it.
    final padded = value.padRight((value.length + 3) & ~3, '=');
    try {
      return Uint8List.fromList(base64Url.decode(padded));
    } on FormatException {
      throw ShareFormatException('$what is not valid base64url');
    }
  }

  /// ArgumentError rather than ShareFormatException: this reads *our own*
  /// publisher key on the way out, so a failure here is a bug in the caller, not
  /// malformed input from a relay or a browser.
  static Uint8List _bytesFromHex(String hex) {
    if (hex.length != 64) {
      throw ArgumentError.value(
        hex.length,
        'publisherPublicKey',
        'must be 64 hex chars',
      );
    }
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) {
        throw ArgumentError.value(
          '<redacted>',
          'publisherPublicKey',
          'must be hex',
        );
      }
      bytes[i] = byte;
    }
    return bytes;
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
