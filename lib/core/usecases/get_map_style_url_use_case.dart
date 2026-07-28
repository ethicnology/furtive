import 'package:furtive/core/datasources/map_remote_data_source.dart';
import 'package:furtive/core/models/preferences_model.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';

/// Resolves the map style to render with, combining the stored preferences
/// (theme, UI locale, tile opt-out) with the remote Protomaps style.
///
/// Kept as a use case — unlike the pass-through ones that were deleted — because
/// it genuinely orchestrates two sources. The former `MapRepository` sat between
/// this and [MapRemoteDataSource] doing nothing but forwarding three fields, so
/// it was dissolved into here.
///
/// Returns null for a tileless map: either no PROTOMAPS_KEY was compiled in
/// (the FOSS/reproducible build) or the user opted out of tile fetches.
class GetMapStyleUrlUseCase {
  GetMapStyleUrlUseCase({
    MapRemoteDataSource? remote,
    PreferencesRepository? preferences,
  }) : _remote = remote ?? MapRemoteDataSource(),
       _preferences = preferences ?? PreferencesRepository();

  final MapRemoteDataSource _remote;
  final PreferencesRepository _preferences;

  Future<String?> call() async {
    final preferences = await _preferences.fetch();
    return _remote.getStyleUrl(
      // Map label language is derived from the UI locale (or the device locale
      // when there is no override). The dedicated "Map Language" picker is
      // gone — two language settings were redundant.
      theme: MapThemeExtension.fromEntity(preferences.mapTheme),
      userLocaleTag: preferences.uiLocale,
      tilesEnabled: preferences.mapTilesEnabled,
    );
  }
}
