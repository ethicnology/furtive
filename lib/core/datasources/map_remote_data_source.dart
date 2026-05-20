import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:furtive/core/database/tables/preferences_table.dart';
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

class MapRemoteDataSource {
  Future<Style> getMapConfig({
    MapThemeColumn theme = MapThemeColumn.light,
    MapLanguageColumn language = MapLanguageColumn.en,
  }) async {
    if (_protomapsKey.isEmpty) {
      throw Exception(
        'Missing PROTOMAPS_KEY. Build with --dart-define=PROTOMAPS_KEY=...',
      );
    }

    final lang = language.name;
    final styleUrl =
        '$_protomapsUrl/${theme.name}/$lang.json?key=$_protomapsKey';

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
      throw 'Protomaps style is not a JSON object: $styleUrl';
    }
    _patchTextFields(styleJson, lang);

    return _buildStyle(styleJson);
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
      final sourceType = value['type'];
      final type =
          TileProviderType.values
              .where((e) => e.name.replaceAll('_', '-') == sourceType)
              .firstOrNull;
      if (type == null) continue;

      dynamic source = value;
      final entryUrl = value['url'] as String?;
      if (entryUrl != null) {
        final tileJsonText = await _httpGet(_withKey(entryUrl));
        final decoded = await compute(jsonDecode, tileJsonText);
        if (decoded is! Map) throw 'Invalid TileJSON at $entryUrl';
        source = decoded;
      }

      final tiles = source['tiles'];
      if (tiles is! List || tiles.isEmpty) continue;
      providers[entry.key] = NetworkVectorTileProvider(
        type: type,
        urlTemplate: _withKey(tiles.first as String),
        maximumZoom: source['maxzoom'] as int? ?? 14,
        minimumZoom: source['minzoom'] as int? ?? 1,
      );
    }
    if (providers.isEmpty) throw 'No tile providers in Protomaps style';

    SpriteStyle? sprites;
    final spriteUri = style['sprite'];
    if (spriteUri is String && spriteUri.trim().isNotEmpty) {
      try {
        final jsonText = await _httpGet(_withKey('$spriteUri.json'));
        final spritesJson = await compute(jsonDecode, jsonText);
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
  String _withKey(String url) {
    if (url.contains('key=')) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}key=$_protomapsKey';
  }

  Future<String> _httpGet(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw 'HTTP ${res.statusCode} fetching $url';
    }
    return res.body;
  }

  Future<Uint8List> _httpGetBytes(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw 'HTTP ${res.statusCode} fetching $url';
    }
    return res.bodyBytes;
  }
}
