import 'package:furtive/features/map/bloc/map_state.dart';

/// Whether the page shows the map or keeps waiting on the loading spinner.
///
/// A null style only blocks while the tile config is still loading; once init
/// has finished with no style (keyless FOSS build), the tileless map renders.
/// A GPS fix is not a prerequisite either: the map opens on a neutral world
/// view and centres on the first valid fix when it arrives.
bool shouldRenderMap(MapState state) {
  final stillLoadingStyle =
      state.styleUrl == null && state.loadingStatus != null;
  return !stillLoadingStyle;
}

/// Whether a location update should move the camera.
///
/// The first fix always centres, leaving the neutral world view at a useful
/// zoom. Later fixes only move the camera while follow mode is active, so a
/// user who panned by hand keeps control of the view.
bool shouldMoveToLocation(MapState previous, MapState current) =>
    current.userLocation != null &&
    previous.userLocation != current.userLocation &&
    (previous.userLocation == null || current.isFollowingUser);
