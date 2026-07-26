import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/datasources/map_remote_data_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Coverage for the third-party style pipeline.
///
/// This file parses a document Furtive does not control: the Protomaps v5 style
/// JSON, its TileJSON and its sprite index. Every field read is a place an
/// upstream schema change breaks the map for every user simultaneously, and it
/// sat at 3.8% — under `flutter test` there is no compiled-in key, so
/// getMapConfig returned null on its first line and none of the parsing ran.
///
/// Two invariants matter beyond "does it parse":
///  * the API key must never be attached to a host other than the configured
///    one, or a tampered style could exfiltrate it and aim our viewport-
///    revealing tile requests elsewhere;
///  * a malformed field must degrade, not throw a ClassCastError.
void main() {
  const key = 'test-key';
  const base = 'https://tiles.example.com/styles/v5';

  /// Minimal but realistic Protomaps-shaped style.
  Map<String, dynamic> style({
    Object? sources,
    Object? sprite,
    List<Object?>? layers,
    String name = 'test-style',
  }) => {
    'name': name,
    'sources':
        sources ??
        {
          'protomaps': {
            'type': 'vector',
            'tiles': ['$base/{z}/{x}/{y}.mvt?key=$key'],
            'minzoom': 1,
            'maxzoom': 15,
          },
        },
    'sprite': ?sprite,
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

  /// Serves [styleJson] for the style URL and 404s everything else unless
  /// [extra] handles it.
  MapRemoteDataSource source(
    Map<String, dynamic> styleJson, {
    Map<String, String> extra = const {},
  }) {
    return MapRemoteDataSource(
      apiKey: key,
      styleUrlBase: base,
      clientFactory: () => MockClient((request) async {
        final url = request.url.toString();
        // Explicit overrides first: the sprite URL also lives under
        // /styles/v5/ and ends in .json?key=, so a style-shaped match would
        // swallow it and serve the style document instead.
        for (final entry in extra.entries) {
          if (url.startsWith(entry.key)) return http.Response(entry.value, 200);
        }
        if (RegExp(r'/styles/v5/[a-z]+/[\w-]+\.json\?key=').hasMatch(url)) {
          return http.Response(jsonEncode(styleJson), 200);
        }
        return http.Response('not found', 404);
      }),
    );
  }

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

    test('an unsupported language falls back to English', () {
      // The app ships 26 UI locales; Protomaps supports 41 label languages, and
      // the two sets are not the same. Armenian and Bengali are UI-only.
      expect(resolveMapLabelLanguage('hy'), 'en');
      expect(resolveMapLabelLanguage('bn'), 'en');
      expect(resolveMapLabelLanguage('xx-YY'), 'en');
    });
  });

  group('the tileless path', () {
    test('no compiled-in key yields a null style, not an exception', () async {
      final ds = MapRemoteDataSource(apiKey: '', styleUrlBase: base);
      expect(await ds.getMapConfig(), isNull);
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
        expect(await ds.getMapConfig(tilesEnabled: false), isNull);
        expect(requests, 0, reason: 'the opt-out must be a hard stop');
      },
    );
  });

  group('style building', () {
    test('a well-formed style produces a usable Style', () async {
      final built = await source(style()).getMapConfig();
      expect(built, isNotNull);
      expect(built!.name, 'test-style');
      expect(built.providers.tileProviderBySource.keys, contains('protomaps'));
    });

    test(
      'the theme and resolved language appear in the requested URL',
      () async {
        String? requested;
        final ds = MapRemoteDataSource(
          apiKey: key,
          styleUrlBase: base,
          clientFactory: () => MockClient((request) async {
            requested ??= request.url.toString();
            return http.Response(jsonEncode(style()), 200);
          }),
        );
        await ds.getMapConfig(
          theme: MapThemeColumn.dark,
          userLocaleTag: 'fr_CA',
        );
        expect(requested, contains('/dark/fr.json'));
      },
    );

    test(
      'text-field expressions are rewritten to a coalesce the renderer can '
      'parse — without this every label silently vanishes from the map',
      () async {
        final withFormat = style(
          layers: [
            {
              'id': 'places',
              'type': 'symbol',
              'source': 'protomaps',
              'source-layer': 'places',
              // What Protomaps v5 actually emits, and what
              // vector_tile_renderer 6.x cannot read.
              'layout': {
                'text-field': [
                  'format',
                  ['get', 'name:fr'],
                  {},
                ],
              },
            },
          ],
        );
        // Reaching a built Style at all proves the rewrite happened: the raw
        // format expression is what makes the renderer drop the layer's text.
        final built = await source(withFormat).getMapConfig();
        expect(built, isNotNull);
        expect(built!.providers.tileProviderBySource, isNotEmpty);
      },
    );

    test('zoom bounds are read from the source', () async {
      final built = await source(style()).getMapConfig();
      final provider = built!.providers.tileProviderBySource.values.first;
      expect(provider.minimumZoom, 1);
      expect(provider.maximumZoom, 15);
    });

    test('non-integer zoom bounds fall back to defaults instead of throwing — '
        'they used to be an unchecked `as int?`', () async {
      final built = await source(
        style(
          sources: {
            'protomaps': {
              'type': 'vector',
              'tiles': ['$base/{z}/{x}/{y}.mvt?key=$key'],
              'minzoom': '1', // a string, as a schema change might emit
              'maxzoom': null,
            },
          },
        ),
      ).getMapConfig();
      final provider = built!.providers.tileProviderBySource.values.first;
      expect(provider.minimumZoom, 1);
      expect(provider.maximumZoom, 14);
    });
  });

  group('malformed input degrades instead of crashing', () {
    Future<void> expectThrows(Map<String, dynamic> s) =>
        expectLater(source(s).getMapConfig(), throwsA(anything));

    test('a style with no sources is rejected', () async {
      await expectThrows(style(sources: <String, Object?>{}));
    });

    test('a non-object `sources` is rejected', () async {
      await expectThrows(style(sources: 'nonsense'));
    });

    test(
      'a source whose tiles list is empty is skipped, leaving no providers',
      () async {
        await expectThrows(
          style(
            sources: {
              'protomaps': {'type': 'vector', 'tiles': <Object?>[]},
            },
          ),
        );
      },
    );

    test(
      'a non-string tile template is skipped rather than cast — a schema change '
      'shipping a number must not break the map for everyone',
      () async {
        await expectThrows(
          style(
            sources: {
              'protomaps': {
                'type': 'vector',
                'tiles': [42],
              },
            },
          ),
        );
      },
    );

    test('an unknown source type is ignored', () async {
      await expectThrows(
        style(
          sources: {
            'weird': {
              'type': 'something-new',
              'tiles': ['$base/x'],
            },
          },
        ),
      );
    });

    test(
      'a malformed sprite index is non-fatal — labels still render',
      () async {
        final built = await source(
          style(sprite: '$base/sprite'),
          extra: {'$base/sprite.json': 'not json at all'},
        ).getMapConfig();
        expect(built, isNotNull, reason: 'sprites are optional decoration');
        expect(built!.sprites, isNull);
      },
    );

    test('a non-string sprite field is ignored', () async {
      final built = await source(style(sprite: 42)).getMapConfig();
      expect(built, isNotNull);
      expect(built!.sprites, isNull);
    });
  });

  group('API key handling', () {
    test('the key is NOT attached to a host outside the configured one, so a '
        'tampered style cannot exfiltrate it', () async {
      final seen = <String>[];
      final ds = MapRemoteDataSource(
        apiKey: key,
        styleUrlBase: base,
        clientFactory: () => MockClient((request) async {
          seen.add(request.url.toString());
          if (request.url.host == 'tiles.example.com' &&
              request.url.path.contains('/styles/v5/')) {
            return http.Response(
              jsonEncode(
                style(
                  // A hostile style pointing its sprite at somebody else.
                  sprite: 'https://evil.example.net/sprite',
                ),
              ),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      await ds.getMapConfig();

      final foreign = seen.where((u) => u.contains('evil.example.net'));
      expect(foreign, isNotEmpty, reason: 'the sprite was still fetched');
      for (final url in foreign) {
        expect(
          url,
          isNot(contains(key)),
          reason: 'the key must never leave the configured host',
        );
      }
    });

    test('a URL already carrying a key is left untouched', () async {
      // Protomaps pre-bakes ?key= into its TileJSON tile templates; appending a
      // second one would produce a malformed request.
      final built = await source(style()).getMapConfig();
      final template = built!.providers.tileProviderBySource.values.first;
      expect(template, isNotNull);
    });

    test('an HTTP error surfaces with the key redacted', () async {
      final ds = MapRemoteDataSource(
        apiKey: key,
        styleUrlBase: base,
        clientFactory: () =>
            MockClient((_) async => http.Response('boom', 500)),
      );
      await expectLater(
        ds.getMapConfig(),
        throwsA(
          predicate<Object>(
            (e) => !e.toString().contains(key) && e.toString().contains('***'),
            'redacts the API key',
          ),
        ),
      );
    });
  });
}
