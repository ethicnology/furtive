import 'package:flutter/widgets.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';

/// The rendering port: everything Furtive needs from a map, and nothing else.
///
/// Its shape was not invented up front. It is the surface the on-device
/// benchmark had to expose to drive two backends interchangeably
/// (integration_test/map_benchmark_app.dart), intersected with what MapPage and
/// ActivityDetailPage actually call. Auditing those two pages showed the real
/// coupling was tiny: three MapController members (`move`, `camera`, `dispose`)
/// and five layer kinds.
///
/// Keeping a port rather than calling MapLibre from the pages buys two things:
/// the old backend stays available for A/B measurement until it is deleted, and
/// the pages stop importing a rendering library at all.
///
/// Note there is no `loadBasemap` step. An earlier draft had one, which was
/// wrong twice over: it duplicated the style-URL construction that
/// MapRemoteDataSource already owns and tests, and being async it forced the
/// pages into an await-then-setState dance. Resolving the basemap is a data
/// concern, so it stays in the data layer and arrives here as a plain string.
abstract class MapView {
  /// Identifies the implementation in logs and benchmark reports.
  String get name;

  /// The map widget.
  ///
  /// [styleUrl] is the resolved basemap descriptor, or null to render tile-less.
  /// Tile-less is a first-class mode, not an error path: it is what a keyless
  /// reproducible build gets, and what a user who declined tile fetches gets.
  /// Every tile request discloses the viewport — and so an approximation of the
  /// live position — to the tile host, so declining must still yield a usable
  /// map. The track is drawn either way.
  ///
  /// [track] is a build parameter rather than something a nested builder can
  /// supply, and MapLibre forces that: its `layers` are immutable value objects
  /// rather than widgets, so a track change necessarily rebuilds this widget.
  /// Callers must therefore keep the 1 s elapsed tick out of the state this
  /// builder watches — see MapPage's activity-only `buildWhen`.
  ///
  /// The cost is bounded, and measured rather than assumed: rebuilding does not
  /// recreate the native view, MapLibre diffs the layer list by value, and the
  /// benchmark's recording scenario drives exactly this path at ~2 ms per frame
  /// with zero frames over budget.
  ///
  /// Segments are styled by kind: active solid, paused in the secondary colour,
  /// and signalLost dashed — a solid line across a GPS outage would assert a
  /// path that was never recorded.
  ///
  /// [onUserGesture] fires when the user pans or zooms by hand, so callers can
  /// drop follow-mode instead of fighting the gesture. It must not fire for
  /// programmatic [moveTo] calls.
  ///
  /// [userPosition] is the live position to draw the "you are here" puck at,
  /// or null for none. It is a parameter rather than something the map fetches
  /// for itself on purpose: the renderer's own location component used to do
  /// that, from a second location engine that bypassed the app's quality
  /// filter and drew a position the rest of the app had rejected. Passing it
  /// in makes one source of truth structural.
  ///
  /// [deviceHeading] is which way the phone is pointing, in degrees clockwise
  /// from true north, or null when no compass is available. Distinct from the
  /// course over ground carried on [userPosition]: a phone can point east
  /// while its owner walks north, so the puck shows them differently.
  ///
  /// [controlsOnLeft] tells the map which bottom corner the caller's floating
  /// controls occupy, so the attribution badge can take the other one. It is
  /// legally required to stay visible, and it was already covered once by the
  /// button column — mirroring the buttons without mirroring the badge would
  /// reintroduce exactly that.
  Widget build({
    required String? styleUrl,
    required ActivityEntity? track,
    required PositionEntity? initialCentre,
    required double initialZoom,
    required double maxZoom,
    required bool showUserLocation,
    required VoidCallback onUserGesture,
    bool controlsOnLeft = false,
    PositionEntity? userPosition,
    double? deviceHeading,
  });

  /// Recentres the camera. A no-op before the map has attached, so callers do
  /// not have to sequence against the widget lifecycle — the previous stack
  /// threw here, which is why MapPage carries a comment about not recentring on
  /// the resume path.
  void moveTo(PositionEntity centre, double zoom);

  /// Current camera zoom, or null before the map has attached.
  double? get currentZoom;

  Future<void> dispose();
}
