import 'dart:convert';
import 'dart:typed_data';

import 'package:furtive_share/furtive_share.dart';
import 'package:test/test.dart';

void main() {
  final secret = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
  const publisher =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  ShareLink link({
    List<String> relays = const ['wss://nos.lol'],
    bool passwordProtected = false,
  }) => ShareLink(
    publisherPublicKey: publisher,
    shareSecret: secret,
    relays: relays,
    passwordProtected: passwordProtected,
  );

  group('round trip', () {
    test('everything survives the fragment', () {
      final parsed = ShareLink.parse(
        link(
          relays: const ['wss://nos.lol', 'wss://relay.primal.net'],
        ).toUri('https://share.example'),
      );

      expect(parsed.publisherPublicKey, publisher);
      expect(parsed.shareSecret, secret);
      expect(parsed.relays, ['wss://nos.lol', 'wss://relay.primal.net']);
      expect(parsed.passwordProtected, isFalse);
    });

    test('the password flag is announced, not discovered', () {
      // A viewer cannot tell "needs a password" from "the share ended" by
      // trying: a wrong master derives a different topic, so nothing matches.
      expect(
        ShareLink.parse(
          link(passwordProtected: true).toFragment(),
        ).passwordProtected,
        isTrue,
      );
    });

    test('the descriptor cannot be mutated after the link is built', () {
      // Key material and a relay list handed out and then changed under the
      // caller is exactly the kind of aliasing a value type must not allow.
      final mutableRelays = ['wss://nos.lol'];
      final mutableSecret = Uint8List.fromList(secret);
      final built = ShareLink(
        publisherPublicKey: publisher,
        shareSecret: mutableSecret,
        relays: mutableRelays,
      );

      mutableRelays.add('wss://evil.test');
      mutableSecret[0] = 0xff;

      expect(built.relays, ['wss://nos.lol']);
      expect(built.shareSecret.first, secret.first);
      final exposedSecret = built.shareSecret;
      exposedSecret[0] = 0xff;
      expect(built.shareSecret.first, secret.first);
      expect(() => built.relays.add('wss://evil.test'), throwsUnsupportedError);
    });

    test('a relay path is preserved', () {
      final parsed = ShareLink.parse(
        link(relays: const ['wss://example.test/nostr']).toFragment(),
      );
      expect(parsed.relays, ['wss://example.test/nostr']);
    });
  });

  group('the secret stays in the fragment', () {
    test('nothing sensitive lands before the #', () {
      final built = link();
      final uri = built.toUri('https://share.example');
      final beforeFragment = uri.substring(0, uri.indexOf('#'));
      final parsed = Uri.parse(uri);

      expect(beforeFragment, 'https://share.example/');
      // The property the whole format rests on: a browser sends the path and the
      // query to the host, and never the fragment. So the descriptor must be
      // entirely inside the fragment and nowhere else.
      expect(parsed.query, isEmpty);
      expect(parsed.path, '/');
      expect(parsed.fragment, built.toFragment());
      for (final segment in built.toFragment().split('.').skip(1)) {
        expect(
          beforeFragment,
          isNot(contains(segment)),
          reason: 'no part of the descriptor may precede the #',
        );
      }
    });

    test('a trailing slash on the viewer base does not double up', () {
      expect(
        link().toUri('https://share.example/'),
        link().toUri('https://share.example'),
      );
    });

    test('the viewer must be a clean HTTPS URL', () {
      for (final base in [
        'http://share.example',
        'https://user:pass@share.example',
        'https://share.example?secret=no',
        'https://share.example/#other',
      ]) {
        expect(() => link().toUri(base), throwsArgumentError, reason: base);
      }
      expect(
        link().toUri('http://localhost:8080'),
        startsWith('http://localhost:8080/#v1.'),
      );
    });

    test('base64url carries no padding, which would need escaping', () {
      expect(link().toFragment(), isNot(contains('=')));
      expect(link().toFragment(), isNot(contains('+')));
      expect(link().toFragment(), isNot(contains('/')));
    });
  });

  group('parsing accepts what a browser hands over', () {
    test('a full link, a bare fragment, or one with a leading #', () {
      final fragment = link().toFragment();

      for (final input in [
        'https://share.example/#$fragment',
        '#$fragment',
        fragment,
      ]) {
        expect(ShareLink.parse(input).publisherPublicKey, publisher);
      }
    });
  });

  group('and refuses what it does not fully understand', () {
    test('an empty fragment', () {
      expect(
        () => ShareLink.parse('https://share.example/#'),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a version from the future', () {
      final parts = link().toFragment().split('.');
      expect(
        () => ShareLink.parse(['v2', ...parts.skip(1)].join('.')),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a missing segment', () {
      final parts = link().toFragment().split('.');
      expect(
        () => ShareLink.parse(parts.take(3).join('.')),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('an oversized fragment is refused before decoding', () {
      expect(
        () => ShareLink.parse('#${'x' * (ShareLink.maxFragmentLength + 1)}'),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('too many relays are refused in both directions', () {
      final relays = [
        for (var i = 0; i <= ShareLink.maxRelays; i++) 'wss://r$i.example',
      ];
      expect(() => link(relays: relays).toFragment(), throwsArgumentError);

      final parts = link().toFragment().split('.');
      parts[3] = base64Url
          .encode(utf8.encode(relays.map((r) => r.substring(6)).join(',')))
          .replaceAll('=', '');
      expect(
        () => ShareLink.parse(parts.join('.')),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a truncated publisher key', () {
      final parts = link().toFragment().split('.');
      parts[1] = parts[1].substring(0, 10);
      expect(
        () => ShareLink.parse(parts.join('.')),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a truncated share secret', () {
      final parts = link().toFragment().split('.');
      parts[2] = parts[2].substring(0, 8);
      expect(
        () => ShareLink.parse(parts.join('.')),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a relay list whose bytes are not UTF-8', () {
      // utf8.decode throws a bare FormatException, which would sail past a
      // caller catching ShareFormatException and surface as an unhandled error.
      final parts = link().toFragment().split('.');
      parts[3] = base64Url.encode([0xff, 0xfe, 0xfd]).replaceAll('=', '');
      expect(
        () => ShareLink.parse(parts.join('.')),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('base64url that is not base64url', () {
      final parts = link().toFragment().split('.');
      parts[2] = 'not*valid*base64';
      expect(
        () => ShareLink.parse(parts.join('.')),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a fragment listing no relay', () {
      // Nothing to subscribe to is not a degraded share, it is an unusable one.
      expect(
        () => ShareLink.parse('v1.${'A' * 43}.${'A' * 43}.'),
        throwsA(isA<ShareFormatException>()),
      );
    });

    test('a relay host smuggling a query, a fragment or credentials', () {
      // The viewer opens a websocket to whatever the link says, and the link is
      // attacker-controlled.
      for (final hostile in [
        'evil.test?x=1',
        'evil.test#y',
        'user:pass@evil.test',
        'evil test',
        r'evil.test\other',
      ]) {
        final parts = link().toFragment().split('.');
        parts[3] = base64Url.encode(utf8.encode(hostile)).replaceAll('=', '');
        expect(
          () => ShareLink.parse(parts.join('.')),
          throwsA(isA<ShareFormatException>()),
          reason: 'must refuse "$hostile"',
        );
      }
    });
  });

  group('refuses to mint a link it could not read back', () {
    test('no relay', () {
      expect(
        () => ShareLink(
          publisherPublicKey: publisher,
          shareSecret: secret,
          relays: const [],
        ).toFragment(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a publisher key that is not hex', () {
      expect(
        () => ShareLink(
          publisherPublicKey: 'z' * 64,
          shareSecret: secret,
          relays: const ['wss://nos.lol'],
        ).toFragment(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a publisher key of the wrong length', () {
      expect(
        () => ShareLink(
          publisherPublicKey: 'ab',
          shareSecret: secret,
          relays: const ['wss://nos.lol'],
        ).toFragment(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('and never puts the key in the error message', () {
      try {
        ShareLink(
          publisherPublicKey: 'z' * 64,
          shareSecret: secret,
          relays: const ['wss://nos.lol'],
        ).toFragment();
        fail('expected an ArgumentError');
      } on ArgumentError catch (e) {
        expect('$e', isNot(contains('zzzz')));
      }
    });
  });

  group('plaintext websockets are unrepresentable', () {
    test('a ws:// relay is refused rather than silently upgraded', () {
      // A plaintext-only relay need not provide TLS on the same host. Rewriting
      // it minted a link that looked secure but could never connect.
      expect(
        () => link(relays: const ['ws://insecure.test']).toFragment(),
        throwsArgumentError,
      );
    });
  });
}
