import 'package:furtive/core/database/tables/preferences_table.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

// Secrets are injected at build time via --dart-define so they never get
// bundled into the APK as a plain asset (which a .env file would be).
// See README for the build command.
const _protomapsUrl = String.fromEnvironment(
  'PROTOMAPS_URL',
  defaultValue: 'https://api.protomaps.com/styles/v5',
);
const _protomapsKey = String.fromEnvironment('PROTOMAPS_KEY');

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

    final styleUrl =
        '$_protomapsUrl/${theme.name}/${language.name}.json?key=$_protomapsKey';
    return await StyleReader(uri: styleUrl, apiKey: _protomapsKey).read();
  }
}
