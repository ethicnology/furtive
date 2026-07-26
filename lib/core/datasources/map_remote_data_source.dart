import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:furtive/core/logs.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

// Secrets are injected at build time via --dart-define so they never get
// bundled into the APK as a plain asset (which a .env file would be).
// See README for the build command.
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
  final lang = tag.split(RegExp(r'[-_]')).first;
  if (lang == 'zh') return 'zh-Hans';
  if (protomapsSupportedLanguages.contains(lang)) return lang;
  return 'en';
}

class MapRemoteDataSource {
  Future<Style?> getMapConfig({
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
    if (_protomapsKey.isEmpty || !tilesEnabled) {
      logs.warning(
        'getMapConfig: tileless map '
        '(keyEmpty: ${_protomapsKey.isEmpty}, tilesEnabled: $tilesEnabled)',
      );
      return null;
    }

    final lang = resolveMapLabelLanguage(userLocaleTag);
    final styleUrl =
        '$_protomapsUrl/${theme.name}/$lang.json?key=$_protomapsKey';
    logs.info('getMapConfig: fetching style ${_redactKey(styleUrl)}');

    // We don't use StyleReader.read() directly because the Protomaps v5
    // style JSON encodes localised labels with a MapLibre `format`
    // expression, and vector_tile_renderer 6.x has no parser for it —
    // result: every text label silently drops out of the rendered map.
    // We fetch the JSON, rewrite each layer's `text-field` to a simple
    // coalesce(get name:LANG, get name) that the renderer DOES parse,
    // then run the rest of StyleReader's pipeline by hand.
    final styleText = await _httpGet(styleUrl);
    final styleJson = await compute(jsonDecode, styleText);
    if (styleJson is! Map<String, dynamic>) {
      throw 'Protomaps style is not a JSON object: ${_redactKey(styleUrl)}';
    }
    _patchTextFields(styleJson, lang);

    final builtStyle = await _buildStyle(styleJson);
    logs.info(
      'getMapConfig: style built (name: ${builtStyle.name}, '
      'providers: ${builtStyle.providers.tileProviderBySource.keys.toList()})',
    );
    return builtStyle;
  }

  /// Walk every layer and replace its `text-field` (which Protomaps emits
  /// as a complex format expression for localisation) with a simple
  /// coalesce(get name:LANG, get name). Layers without a text-field are
  /// left alone.
  void _patchTextFields(Map<String, dynamic> style, String lang) {
    final layers = style['layers'];
    if (layers is! List) return;
    for (final layer in layers) {
      if (layer is! Map) continue;
      final layout = layer['layout'];
      if (layout is! Map) continue;
      if (layout['text-field'] == null) continue;
      layout['text-field'] = [
        'coalesce',
        ['get', 'name:$lang'],
        ['get', 'name'],
      ];
    }
  }

  /// Replicates the post-fetch pipeline of vector_map_tiles' [StyleReader]
  /// (providers + sprites + theme parsing) so we can feed it our patched
  /// style JSON.
  Future<Style> _buildStyle(Map<String, dynamic> style) async {
    final sources = style['sources'];
    if (sources is! Map) {
      throw 'Protomaps style has no sources';
    }

    final providers = <String, VectorTileProvider>{};
    for (final entry in sources.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final sourceKey = entry.key;
      if (sourceKey is! String) continue;
      final sourceType = value['type'];
      final type = TileProviderType.values
          .where((e) => e.name.replaceAll('_', '-') == sourceType)
          .firstOrNull;
      if (type == null) continue;

      // Typed as Map rather than `dynamic`: this whole block parses a
      // third-party document, so every access below is a place a Protomaps
      // schema change can break the map for every user at once. With
      // `dynamic source` the analyser could not see any of it (which is what
      // strict-casts / avoid_dynamic_calls now forbid) and each read compiled to
      // an unchecked runtime cast.
      Map<Object?, Object?> source = value;
      final entryUrl = value['url'];
      if (entryUrl is String) {
        final tileJsonText = await _httpGet(_withKey(entryUrl));
        final decoded = await compute(jsonDecode, tileJsonText);
        if (decoded is! Map) throw 'Invalid TileJSON at $entryUrl';
        source = decoded;
      }

      final tiles = source['tiles'];
      if (tiles is! List || tiles.isEmpty) continue;
      // Don't unchecked-cast the first entry — a future Protomaps schema change
      // shipping a non-string would throw and break the map for everyone until
      // we ship a patch. Same reasoning for the zoom bounds below: a
      // non-integer there used to be an unchecked `as int?`.
      final first = tiles.first;
      if (first is! String) continue;
      final maxZoom = source['maxzoom'];
      final minZoom = source['minzoom'];
      providers[sourceKey] = NetworkVectorTileProvider(
        type: type,
        urlTemplate: _withKey(first),
        maximumZoom: maxZoom is int ? maxZoom : 14,
        minimumZoom: minZoom is int ? minZoom : 1,
      );
    }
    if (providers.isEmpty) throw 'No tile providers in Protomaps style';

    SpriteStyle? sprites;
    final spriteUri = style['sprite'];
    if (spriteUri is String && spriteUri.trim().isNotEmpty) {
      try {
        final jsonText = await _httpGet(_withKey('$spriteUri.json'));
        final spritesJson = await compute(jsonDecode, jsonText);
        // SpriteIndexReader.read wants a Map<String, dynamic>; jsonDecode
        // returns Object?, so check rather than cast — a malformed sprite index
        // must fall through to the catch below (sprites are non-fatal) instead
        // of throwing a ClassCastError.
        if (spritesJson is! Map<String, dynamic>) {
          throw 'Invalid sprite index at $spriteUri.json';
        }
        sprites = SpriteStyle(
          atlasProvider: () => _httpGetBytes(_withKey('$spriteUri.png')),
          index: SpriteIndexReader().read(spritesJson),
        );
      } catch (_) {
        // Sprites are non-fatal — labels still render without them.
      }
    }

    return Style(
      name: style['name'] as String?,
      theme: ThemeReader().read(style),
      providers: TileProviders(providers),
      sprites: sprites,
    );
  }

  /// Protomaps gates every resource (tiles, sprites, TileJSON) on the
  /// same API key; URIs in the v5 style JSON are emitted without one.
  // Strip the API key before a URL goes into a thrown/logged error string.
  static String _redactKey(String url) =>
      url.replaceAll(RegExp(r'key=[^&]*'), 'key=***');

  /// Host the API key may be appended to. Only URLs on the configured
  /// Protomaps host receive the key, so a compromised/MITM'd style JSON that
  /// smuggles in a third-party `url`/`sprite`/`tiles` host can't exfiltrate
  /// the key (or turn our tile requests, which leak the viewport, toward an
  /// attacker). Parsed once from _protomapsUrl.
  static final String _keyHost = Uri.parse(_protomapsUrl).host;

  String _withKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    // Exact query-parameter check (not a substring) and host allowlist.
    if (uri.queryParameters.containsKey('key')) return url;
    if (uri.host != _keyHost) return url;
    // Textual concatenation, NOT uri.replace(queryParameters: ...): a tile
    // URL template contains literal placeholders like {z}/{x}/{y}, and
    // Uri.replace re-encodes the whole query/path component, turning them
    // into %7Bz%7D/%7Bx%7D/%7By%7D — NetworkVectorTileProvider substitutes
    // placeholders via a regex that only matches the unencoded braces, so
    // every tile request would 404. Currently masked because Protomaps'
    // TileJSON responses already embed `?key=` in their own tile templates
    // (the early return above), but this path is hit directly for `sprite`/
    // style-level `url` fields, and would be hit for tiles too if Protomaps
    // ever stopped pre-baking the key.
    final separator = url.contains('?') ? '&' : '?';
    return '$url$separator'
        'key=$_protomapsKey';
  }

  // Cap every map resource fetch (TileJSON, style, sprites, tiles) so a hung
  // Protomaps connection can't leave the map-setup future pending forever.
  // Matches the trace source's timeout.
  static const _httpTimeout = Duration(seconds: 30);

  /// Metadata fetches (style JSON, TileJSON, sprite atlas) are small; bound
  /// them so a hostile/misbehaving response can't exhaust memory. Tiles proper
  /// go through NetworkVectorTileProvider and aren't covered here.
  static const _maxResponseBytes = 16 * 1024 * 1024;

  Future<Uint8List> _httpGetBytesCapped(String url) async {
    final client = http.Client();
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

  Future<Uint8List> _httpGetBytes(String url) => _httpGetBytesCapped(url);
}
