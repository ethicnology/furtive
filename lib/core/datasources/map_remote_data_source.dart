import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/logs.dart';
import 'package:http/http.dart' as http;

// Build-time configuration, injected via --dart-define rather than shipped as
// a .env asset. Configuration, not confidentiality: a --dart-define becomes a
// compile-time constant inside libapp.so, and `strings` recovers it from any
// published APK. A tile key the client must present to the provider cannot be
// secret in the first place — restrict it provider-side instead. An empty key
// yields the tileless FOSS build. See README for the build command.
const _protomapsUrl = String.fromEnvironment(
  'PROTOMAPS_URL',
  defaultValue: 'https://api.protomaps.com/styles/v5',
);
const _protomapsKey = String.fromEnvironment('PROTOMAPS_KEY');

/// BCP-47 codes supported by Protomaps v5 (docs.protomaps.com/basemaps/localization).
/// Used both to validate the language picked for the style URL and to pick
/// the right `name:xx` field when rewriting label expressions.
const Set<String> protomapsSupportedLanguages = {
  'ar',
  'bg',
  'zh-Hans',
  'zh-Hant',
  'hr',
  'cs',
  'da',
  'nl',
  'en',
  'et',
  'fi',
  'fr',
  'de',
  'el',
  'he',
  'hi',
  'hu',
  'id',
  'ga',
  'it',
  'ja',
  'ko',
  'lv',
  'lt',
  'mt',
  'mr',
  'ne',
  'no',
  'fa',
  'pl',
  'pt',
  'ro',
  'ru',
  'sk',
  'sl',
  'es',
  'sv',
  'tr',
  'uk',
  'ur',
  'vi',
};

/// Resolve the best Protomaps label language for the given locale tag, or
/// for the device locale when [userLocaleTag] is null. Falls back to 'en'
/// when no match exists. Special-cases Chinese: a bare 'zh' maps to
/// 'zh-Hans' (simplified), which has the wider speaker base.
String resolveMapLabelLanguage(String? userLocaleTag) {
  final tag =
      userLocaleTag ?? PlatformDispatcher.instance.locale.toLanguageTag();
  if (protomapsSupportedLanguages.contains(tag)) return tag;
  if (tag == 'zh-TW' ||
      tag == 'zh_TW' ||
      tag == 'zh-HK' ||
      tag == 'zh_HK' ||
      tag == 'zh-MO' ||
      tag == 'zh_MO') {
    return 'zh-Hant';
  }
  final lang = tag.split(RegExp(r'[-_]')).first;
  if (lang == 'zh') return 'zh-Hans';
  if (protomapsSupportedLanguages.contains(lang)) return lang;
  return 'en';
}

class MapRemoteDataSource {
  /// [clientFactory], [apiKey] and [styleUrlBase] default to the real HTTP
  /// client and the compile-time `--dart-define` values, so production call
  /// sites stay `MapRemoteDataSource()`.
  ///
  /// They exist because this class parses a THIRD-PARTY document — the Protomaps
  /// style JSON and its TileJSON — and every field it reads is a place a schema
  /// change can break the map for every user at once. Without a seam, none of
  /// that parsing was reachable from a test: under `flutter test` there is no
  /// compiled-in key, so getStyleUrl returned null on its first line and the
  /// remaining ~100 lines never ran.
  ///
  /// A factory rather than a client instance: each request closes its client
  /// when done, so a single injected instance would be unusable after the first
  /// call.
  MapRemoteDataSource({
    http.Client Function()? clientFactory,
    String? apiKey,
    String? styleUrlBase,
  }) : _newClient = clientFactory ?? http.Client.new,
       _apiKey = apiKey ?? _protomapsKey,
       _styleUrlBase = styleUrlBase ?? _protomapsUrl;

  final http.Client Function() _newClient;
  final String _apiKey;
  final String _styleUrlBase;

  /// Resolves the basemap style URL to hand to the renderer, or null to render
  /// tile-less.
  ///
  /// Returns a URL rather than a parsed style because MapLibre Native fetches
  /// and parses the style itself. Protomaps' own style is therefore used
  /// verbatim — no `text-field` rewriting, no hand-rolled sprite pipeline.
  ///
  /// The style is still fetched once here purely to validate it. That looks
  /// redundant (the native SDK will fetch it again, though its HTTP cache
  /// usually absorbs that) and it is deliberate: maplibre 0.3.5 emits no
  /// style-load-failure event, so an expired key or a captive portal would
  /// otherwise leave a silent blank map with no way to detect it. Validating in
  /// Dart keeps the deliberate tile-less fallback that the keyless build
  /// already relies on. Drop this once upstream exposes a failure event.
  Future<String?> getStyleUrl({
    MapThemeColumn theme = MapThemeColumn.light,
    String? userLocaleTag,
    bool tilesEnabled = true,
  }) async {
    // No key → the FOSS / reproducible build. Return null instead of throwing
    // so the app degrades to a functional, tileless map (record activities,
    // see your track on a blank canvas) rather than getting stuck on a spinner.
    //
    // tilesEnabled == false → the user opted out (Preferences) even though a
    // key was compiled in. Every map-tile request reveals the current
    // viewport — and therefore an approximation of the live position, and
    // past activity locations via the detail page — to the tile host. This
    // makes a keyed build behave exactly like the keyless one: same
    // tileless map, zero network calls to Protomaps. See
    // docs/AUDIT-2026-07.md §5.
    if (_apiKey.isEmpty || !tilesEnabled) {
      logs.warning(
        'getStyleUrl: tileless map '
        '(keyEmpty: ${_apiKey.isEmpty}, tilesEnabled: $tilesEnabled)',
      );
      return null;
    }

    final lang = resolveMapLabelLanguage(userLocaleTag);
    final styleUrl = '$_styleUrlBase/${theme.name}/$lang.json?key=$_apiKey';
    logs.info('getStyleUrl: validating style ${_redactKey(styleUrl)}');

    final styleText = await _httpGet(styleUrl);
    final styleJson = await compute(jsonDecode, styleText);
    if (styleJson is! Map<String, dynamic>) {
      throw 'Protomaps style is not a JSON object: ${_redactKey(styleUrl)}';
    }
    // A 200 carrying a JSON object that is not a style would still leave the
    // native SDK blank, so check the one field that must be there.
    if (styleJson['layers'] is! List) {
      throw 'Protomaps style has no layers: ${_redactKey(styleUrl)}';
    }
    logs.info(
      'getStyleUrl: style valid (${(styleJson['layers'] as List).length}'
      ' layers)',
    );
    return styleUrl;
  }

  // Strip the API key before a URL goes into a thrown/logged error string.
  static String _redactKey(String url) =>
      url.replaceAll(RegExp(r'key=[^&]*'), 'key=***');

  // Cap every map resource fetch (TileJSON, style, sprites, tiles) so a hung
  // Protomaps connection can't leave the map-setup future pending forever.
  // Matches the trace source's timeout.
  static const _httpTimeout = Duration(seconds: 30);

  /// Metadata fetches (style JSON, TileJSON, sprite atlas) are small; bound
  /// them so a hostile/misbehaving response can't exhaust memory. Tiles proper
  /// go through NetworkVectorTileProvider and aren't covered here.
  static const _maxResponseBytes = 16 * 1024 * 1024;

  Future<Uint8List> _httpGetBytesCapped(String url) async {
    final client = _newClient();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(_httpTimeout);
      if (response.statusCode != 200) {
        throw 'HTTP ${response.statusCode} fetching ${_redactKey(url)}';
      }
      final declared = response.contentLength;
      if (declared != null && declared > _maxResponseBytes) {
        throw 'Response too large ($declared B) fetching ${_redactKey(url)}';
      }
      final chunks = <List<int>>[];
      var total = 0;
      await for (final chunk in response.stream.timeout(_httpTimeout)) {
        total += chunk.length;
        if (total > _maxResponseBytes) {
          throw 'Response too large (> $_maxResponseBytes B) fetching '
              '${_redactKey(url)}';
        }
        chunks.add(chunk);
      }
      return Uint8List.fromList(chunks.expand((c) => c).toList());
    } finally {
      client.close();
    }
  }

  Future<String> _httpGet(String url) async =>
      utf8.decode(await _httpGetBytesCapped(url));
}
