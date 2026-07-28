import 'dart:async';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/widgets.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/map/map_view.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/km_milestone_chip.dart';
import 'package:maplibre/maplibre.dart' as ml;

/// [MapView] backed by MapLibre Native.
///
/// WHY THIS REPLACES flutter_map + vector_map_tiles
///
/// Measured on device (Pixel 5, profile build, one run, see
/// integration_test/map_benchmark_app.dart):
///
///   zoom_sweep        build avg   raster p90   frames over 16.7 ms
///   vector_map_tiles     1.63ms       8.17ms                     5
///   maplibre             0.44ms       3.35ms                     0
///
/// Zoom is the one scenario where the old stack janks consistently: it
/// rasterises per zoom level, so every step stalls. MapLibre renders vectors
/// continuously and stayed inside budget throughout.
///
/// What it does NOT buy, and this was measured too: an idle map costs zero
/// dropped frames either way, and the recording loop costs ~2 ms a frame with no
/// jank in both. Furtive's central use case had no rendering problem to fix, and
/// an earlier claim in this migration that redrawing the polyline per GPS fix
/// was expensive turned out to be false.
///
/// The rest of the case is structural rather than performance:
///  * Protomaps' official styles are consumed unmodified. The old stack needed
///    `_patchTextFields` because vector_tile_renderer 6.x cannot parse MapLibre
///    `format` expressions, and a real Protomaps style contains 91 of them
///    nested in its label logic. Patching them away replaced Protomaps'
///    multi-script fallback with a flat coalesce.
///  * Dropping vector_tile_renderer removes the `protobuf ^3` ceiling it imposes
///    through vector_tile, which is what made `pmtiles` 2.x unresolvable.
///  * MapLibre ships an OfflineManager.
///
/// Costs accepted knowingly: a large opaque native binary in a project whose
/// selling point is auditability; the native SDK version must stay pinned (see
/// android/app/build.gradle.kts) because upstream publishes pre-releases into
/// the `13.0.+` range; glyphs and sprites are fetched from protomaps.github.io
/// until they are bundled; and release-mode obfuscation must stay off, since
/// upstream has had two release-only rendering bugs tied to R8.
class MapLibreMapView implements MapView {
  ml.MapController? _controller;

  @override
  String get name => 'maplibre';

  @override
  double? get currentZoom => _controller?.getCamera().zoom;

  @override
  void moveTo(PositionEntity centre, double zoom) {
    // Guarded because a non-finite centre poisons the native camera and every
    // later gesture throws. LocationRepository already drops these at source;
    // this is the belt to that braces.
    if (!centre.latitude.isFinite || !centre.longitude.isFinite) return;
    // Fire-and-forget: the native camera move is async and no caller awaits a
    // recentre.
    unawaited(
      _controller?.moveCamera(
        center: ml.Geographic(lon: centre.longitude, lat: centre.latitude),
        zoom: zoom,
      ),
    );
  }

  @override
  Widget build({
    required String? styleUrl,
    required ActivityEntity? track,
    required PositionEntity? initialCentre,
    required double initialZoom,
    required double maxZoom,
    required bool showUserLocation,
    required VoidCallback onUserGesture,
  }) {
    final centre = initialCentre;
    return ml.MapLibreMap(
      options: ml.MapOptions(
        // An empty style renders MapLibre's own blank canvas, which is exactly
        // the tile-less mode: the track still draws over it.
        initStyle: styleUrl ?? '',
        initCenter: centre == null
            ? null
            : ml.Geographic(lon: centre.longitude, lat: centre.latitude),
        initZoom: initialZoom,
        maxZoom: maxZoom,
      ),
      // Without this the map cannot be panned horizontally at all, and dragging
      // sideways flips to the Activities tab instead.
      //
      // MapPage lives inside the bottom navigation's PageView. A Flutter widget
      // competes for a drag in the gesture arena and flutter_map used to win it;
      // an Android platform view does not get that for free — the PageView
      // recognises the horizontal drag first and the touches never reach the
      // native map. Claiming the gesture eagerly inside the map's bounds fixes
      // it, at the deliberate cost of no longer being able to swipe between tabs
      // from the map page. That is the right trade for a map, and the bottom bar
      // still switches tabs.
      //
      // Vertical drags were never affected, which is why this survived the first
      // round of on-device checks: only a horizontal swipe is contested.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      onMapCreated: (controller) => _controller = controller,
      onStyleLoaded: (_) async {
        if (!showUserLocation) return;
        try {
          // The native LocationComponent: pulse, accuracy circle and heading,
          // replacing what flutter_map_location_marker drew in Dart. Note
          // maplibre_ios currently honours almost none of these flags, so iOS
          // gets the stock blue dot.
          await _controller?.enableLocation();
        } catch (e, s) {
          // Never fatal: a map without the blue dot is still a usable map.
          logs.warning('MapLibre: enableLocation failed', error: e, trace: s);
        }
      },
      onEvent: (event) {
        // Telling a user gesture apart from our own moveCamera is what stops
        // follow-mode fighting the user. `MapEventUserInput` would be the
        // obvious choice but does not fire on pan/drag as of 0.3.5 (upstream
        // #544); StartMoveCamera carries the reason and does fire.
        // Verified on device: a pan reports apiGesture, while our own moveCamera
        // reports apiAnimation and so is correctly ignored here.
        if (event is ml.MapEventStartMoveCamera &&
            event.reason == ml.CameraChangeReason.apiGesture) {
          onUserGesture();
        }
      },
      layers: [if (track != null) ..._trackLayers(track)],
      children: [
        if (track != null) _milestones(track),
        // Legally required whenever tiles are shown: the basemap is Protomaps
        // rendering OpenStreetMap data, and ODbL 4.3 plus Protomaps' terms both
        // demand visible credit. SourceAttribution reads it out of the loaded
        // style, so it is correct by construction and self-removes on the
        // tile-less map.
        // bottomLeft, not the default bottomRight: the Follow/Start/Pause FAB
        // column occupies the bottom right and covered all but a sliver of the
        // attribution badge, which does not satisfy "visible credit".
        if (styleUrl != null)
          const ml.SourceAttribution(alignment: Alignment.bottomLeft),
      ],
    );
  }

  /// One layer per segment, so a signalLost stretch can be dashed while the rest
  /// stays solid. Drawing a solid line across a GPS outage would assert a path
  /// that was never recorded; leaving a gap reads as a rendering bug. Dashes say
  /// "unknown".
  Iterable<ml.Layer> _trackLayers(ActivityEntity track) {
    final layers = <ml.Layer>[];
    for (final segment in track.segments) {
      final chain = <ml.Position>[
        for (final point in segment.points)
          ml.Geographic(
            lon: point.position.longitude,
            lat: point.position.latitude,
          ),
      ];
      // A single-point segment has no line to draw. Common: every segment is
      // one point long for the first fix after a resume.
      if (chain.length < 2) continue;
      layers.add(
        ml.PolylineLayer(
          polylines: [ml.Feature(geometry: ml.LineString.from(chain))],
          color: segment.isActive
              ? AppColors.primary.background
              : AppColors.secondary.background,
          width: 4,
          dashArray: segment.isSignalLost ? const [2, 3] : null,
        ),
      );
    }
    return layers;
  }

  /// Km markers as Flutter widgets rather than a symbol layer, so the existing
  /// chip renders unchanged and no sprite has to be generated. Cheap here: one
  /// marker per kilometre, most of them off-screen at a following zoom.
  Widget _milestones(ActivityEntity track) => ml.WidgetLayer(
    markers: [
      for (final milestone in track.kmMilestones)
        ml.Marker(
          point: ml.Geographic(
            lon: milestone.position.longitude,
            lat: milestone.position.latitude,
          ),
          size: const Size.square(28),
          child: KmMilestoneChip(label: '${milestone.km}'),
        ),
    ],
  );

  @override
  Future<void> dispose() async {
    _controller = null;
  }
}
