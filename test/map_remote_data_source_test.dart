import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/datasources/map_remote_data_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Coverage for basemap resolution.
///
/// This file shrank a lot when rendering moved to MapLibre Native, and that is
/// the point: the data source no longer parses the Protomaps style at all, so
/// the sprite index, the TileJSON, the per-source zoom bounds and the
/// `text-field` rewriting are gone along with the tests that guarded them. The
/// style is now consumed verbatim by the renderer.
///
/// One deleted guard deserves a note rather than silent removal. The old code
/// appended the API key to URLs it read *out of* the style document, so it
/// needed a host allowlist to stop a tampered style exfiltrating the key. That
/// code no longer exists: the key is only ever placed in the one URL we build
/// ourselves, so the guard is replaced by construction, which is stronger than
/// a test. The residual risk moved rather than vanished — MapLibre Native now
/// follows whatever hosts the style names (today protomaps.github.io for glyphs
/// and sprites), and that fetching is no longer under Dart's control.
///
/// What still matters here:
///  * the tile opt-out and the keyless build must be hard stops, since every
///    tile request discloses the viewport;
///  * an unusable style must degrade to the tileless map rather than leave a
///    silently blank one, because maplibre 0.3.5 reports no style-load failure;
///  * the key must never appear in an error or log line.
void main() {
  const key = 'test-key';
  const base = 'https://tiles.example.com/styles/v5';

  /// Minimal style with the one field the validator insists on.
  Map<String, dynamic> style({List<Object?>? layers}) => {
    'name': 'test-style',
    'layers':
        layers ??
        [
          {
            'id': 'roads',
            'type': 'line',
            'source': 'protomaps',
            'source-layer': 'roads',
          },
        ],
  };

  /// Serves [body] for any style URL, 404s everything else.
  MapRemoteDataSource source(Object? body, {int status = 200}) =>
      MapRemoteDataSource(
        apiKey: key,
        styleUrlBase: base,
        clientFactory: () => MockClient((request) async {
          final url = request.url.toString();
          if (RegExp(r'/styles/v5/[a-z]+/[\w-]+\.json\?key=').hasMatch(url)) {
            return http.Response(
              body is String ? body : jsonEncode(body),
              status,
            );
          }
          return http.Response('not found', 404);
        }),
      );

  group('resolveMapLabelLanguage', () {
    test('an exactly supported tag is used as-is', () {
      expect(resolveMapLabelLanguage('fr'), 'fr');
      expect(resolveMapLabelLanguage('zh-Hant'), 'zh-Hant');
    });

    test('a regional tag falls back to its base language', () {
      expect(resolveMapLabelLanguage('fr_CA'), 'fr');
      expect(resolveMapLabelLanguage('pt-BR'), 'pt');
    });

    test('bare zh maps to simplified, which has the wider speaker base', () {
      expect(resolveMapLabelLanguage('zh'), 'zh-Hans');
      expect(resolveMapLabelLanguage('zh_CN'), 'zh-Hans');
    });

    test('traditional-Chinese regions map to traditional labels', () {
      expect(resolveMapLabelLanguage('zh-TW'), 'zh-Hant');
      expect(resolveMapLabelLanguage('zh_HK'), 'zh-Hant');
      expect(resolveMapLabelLanguage('zh-MO'), 'zh-Hant');
    });

    test('an unsupported language falls back to English', () {
      // The app ships 26 UI locales; Protomaps supports 41 label languages, and
      // the two sets are not the same. Armenian and Bengali are UI-only.
      expect(resolveMapLabelLanguage('hy'), 'en');
      expect(resolveMapLabelLanguage('bn'), 'en');
      expect(resolveMapLabelLanguage('xx-YY'), 'en');
    });
  });

  group('the tileless path', () {
    test('no compiled-in key yields a null URL, not an exception', () async {
      final ds = MapRemoteDataSource(apiKey: '', styleUrlBase: base);
      expect(await ds.getStyleUrl(), isNull);
    });

    test(
      'a keyed build with the tile opt-out on behaves exactly like the keyless '
      'build — no request is made at all',
      () async {
        var requests = 0;
        final ds = MapRemoteDataSource(
          apiKey: key,
          styleUrlBase: base,
          clientFactory: () => MockClient((_) async {
            requests++;
            return http.Response('{}', 200);
          }),
        );
        expect(await ds.getStyleUrl(tilesEnabled: false), isNull);
        expect(requests, 0, reason: 'the opt-out must be a hard stop');
      },
    );
  });

  group('URL resolution', () {
    test('a valid style yields the URL the renderer should load', () async {
      final url = await source(style()).getStyleUrl();
      expect(url, '$base/light/en.json?key=$key');
    });

    test('the theme selects the Protomaps flavour', () async {
      // The five MapThemeColumn values are named after Protomaps' flavours
      // precisely so this stays a name substitution rather than a lookup table.
      for (final theme in MapThemeColumn.values) {
        expect(
          await source(style()).getStyleUrl(theme: theme),
          '$base/${theme.name}/en.json?key=$key',
          reason: 'flavour ${theme.name}',
        );
      }
    });

    test('the resolved language lands in the path', () async {
      expect(
        await source(style()).getStyleUrl(userLocaleTag: 'pt-BR'),
        '$base/light/pt.json?key=$key',
      );
    });

    test('the key is carried in the returned URL', () async {
      // Not incidental: MapLibre Native fetches this URL itself and Protomaps
      // gates the style on the key, so stripping it would blank the map.
      final url = await source(style()).getStyleUrl();
      expect(url, contains('key=$key'));
    });
  });

  group('an unusable style degrades to the tileless map', () {
    // Each of these must throw so the caller falls back deliberately. Handing a
    // bad URL to MapLibre instead would render a blank map with no signal,
    // because 0.3.5 has no style-load-failure event.
    test('an HTTP error surfaces, with the key redacted', () async {
      await expectLater(
        source(style(), status: 500).getStyleUrl(),
        throwsA(
          isA<String>()
              .having((e) => e, 'message', contains('500'))
              .having((e) => e, 'message', isNot(contains(key)))
              .having((e) => e, 'message', contains('key=***')),
        ),
      );
    });

    test('a body that is not JSON at all is rejected', () async {
      await expectLater(
        source('<html>nope</html>').getStyleUrl(),
        throwsA(anything),
      );
    });

    test('valid JSON that is not an object is rejected', () async {
      await expectLater(source([1, 2, 3]).getStyleUrl(), throwsA(anything));
    });

    test('a JSON object with no layers is rejected', () async {
      // A 200 carrying an error document, or a captive portal's JSON, would
      // otherwise be handed to the renderer as a valid style.
      await expectLater(
        source({'name': 'no-layers'}).getStyleUrl(),
        throwsA(
          isA<String>().having((e) => e, 'message', contains('no layers')),
        ),
      );
    });

    test('a non-list layers field is rejected', () async {
      await expectLater(
        source({'layers': 'roads'}).getStyleUrl(),
        throwsA(anything),
      );
    });

    test('the error never leaks the key', () async {
      await expectLater(
        source('<html>nope</html>').getStyleUrl(),
        throwsA(
          predicate<Object>(
            (e) => !e.toString().contains(key),
            'no API key in the message',
          ),
        ),
      );
    });
  });
}
