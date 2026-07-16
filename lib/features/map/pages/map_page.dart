import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/activity_stats_widget.dart';
import 'package:furtive/core/widgets/hold_to_confirm_button.dart';
import 'package:furtive/core/widgets/km_milestones_layer.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:furtive/core/global.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/activities/pages/activity_detail_page.dart';
import 'package:furtive/core/entities/trace_entity.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

String _loadingMessage(AppLocalizations l10n, LoadingStatus status) =>
    switch (status) {
      LoadingStatus.localizing => l10n.mapLoadingLocalizing,
      LoadingStatus.loadingMap => l10n.mapLoadingMap,
      LoadingStatus.loadingTraces => l10n.mapLoadingTraces,
      LoadingStatus.startingActivity => l10n.mapStartingActivity,
    };

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with AutomaticKeepAliveClientMixin {
  final _mapController = MapController();
  static const _kFloatingActionButtonWidth = 115.0;

  // Stay alive across BottomNavigation tab switches so the F6 cease →
  // stats listener keeps firing even when the user is on Activities or
  // Settings.
  @override
  bool get wantKeepAlive => true;
  StreamSubscription<MapState>? _ceaseSub;

  @override
  void initState() {
    super.initState();
    // F6: route to the activity stats page when the running activity ends
    // (the user holds Stop). We track the
    // previous activity manually since BlocListener's listener can't see
    // the pre-transition state and side-effecting listenWhen is fragile.
    final bloc = context.read<MapBloc>();
    // Trigger location/map init the first time the page mounts. Safe to
    // call repeatedly — _onInitMap leaves an already-open position stream
    // untouched (re-opening it would drop in-flight fixes) and guards
    // concurrent opens against each other (see MapBloc._ensurePositionStreamOpen) —
    // but AutomaticKeepAliveClientMixin keeps this State alive across tab
    // switches so it only fires once per cold start. The onboarded
    // cold-start path lands here; the wizard-finish path fires InitMap
    // explicitly before navigating.
    if (bloc.state.style == null) bloc.add(const InitMap());
    ActivityEntity? prev = bloc.state.activity;
    _ceaseSub = bloc.stream.listen((state) {
      if (prev != null && state.activity == null && mounted) {
        final ceased = prev!;
        // Only push when this page's route is actually on top. The State is
        // kept alive across tab switches, so `mounted` alone would let a cease
        // push the detail page on top of whatever the user is currently
        // looking at.
        final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (isCurrent) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ActivityDetailPage(activity: ceased),
            ),
          );
        }
      }
      prev = state.activity;
    });
  }

  @override
  void dispose() {
    _ceaseSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final bloc = context.read<MapBloc>();

    return MultiBlocListener(
      listeners: [
        BlocListener<MapBloc, MapState>(
          listenWhen: (previous, current) => previous.error != current.error,
          listener: (context, state) {
            if (state.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.error!.message),
                  backgroundColor: kDestructive,
                  duration: const Duration(seconds: 3),
                ),
              );
              context.read<MapBloc>().add(const ClearError());
            }
          },
        ),
        BlocListener<MapBloc, MapState>(
          listenWhen: (previous, current) =>
              previous.trackingGap != current.trackingGap &&
              current.trackingGap != null,
          listener: (context, state) {
            final gap = state.trackingGap!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).mapTrackingGapMsg(gap.inSeconds),
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                ),
                backgroundColor: kWarning,
                duration: const Duration(seconds: 6),
              ),
            );
            context.read<MapBloc>().add(const ClearTrackingGap());
          },
        ),
        BlocListener<MapBloc, MapState>(
          // current.activity != null excludes the failure path: on a failed
          // StartActivity, the catch block emits an error (loadingStatus
          // stays startingActivity) and the finally block then clears it to
          // null WITHOUT an activity ever having been set — without this
          // check, that transition matched too and showed a big "Activity
          // started" toast on top of the error snackbar. See M11 in
          // REVIEW-2026-07-FULL-APP.md.
          listenWhen: (previous, current) =>
              previous.loadingStatus == LoadingStatus.startingActivity &&
              current.loadingStatus == null &&
              current.activity != null,
          listener: (context, state) {
            final screenSize = MediaQuery.of(context).size;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).mapActivityStartedMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                margin: EdgeInsets.only(
                  bottom: screenSize.height * 0.25,
                  left: screenSize.width * 0.1,
                  right: screenSize.width * 0.1,
                ),
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        BlocListener<MapBloc, MapState>(
          // Fire ONLY on a fresh start: an activity that already existed with
          // no points just got its first one. Requiring previous.activity to be
          // non-null deliberately excludes the cold-start resume path (where
          // the activity appears already populated) — resuming must NOT call
          // _mapController.move, because the resumed activity is emitted while
          // the map is still loading/unmounted and move() throws on an
          // unattached controller. On resume the camera stays on the user's
          // current location instead of jumping to the old track start.
          listenWhen: (previous, current) =>
              previous.activity != null &&
              previous.activity!.points.isEmpty &&
              current.activity != null &&
              current.activity!.points.isNotEmpty,
          listener: (context, state) {
            final firstPoint = state.activity!.points.first;
            // Belt-and-suspenders: LocationRepository already drops
            // non-finite GPS frames so points.first should always be
            // finite, but if anything ever lets a NaN through, calling
            // _mapController.move(LatLng(NaN,NaN)) poisons the camera and
            // every subsequent gesture/tile-update throws — observed in
            // production logs prior to the LocationRepository fix.
            if (!firstPoint.position.latitude.isFinite ||
                !firstPoint.position.longitude.isFinite) {
              return;
            }
            _mapController.move(firstPoint.position.toLatLng(), Global.maxZoom);
          },
        ),
        BlocListener<MapBloc, MapState>(
          listenWhen: (previous, current) =>
              current.isFollowingUser &&
              current.userLocation != null &&
              previous.userLocation != current.userLocation,
          listener: (context, state) {
            final loc = state.userLocation!;
            if (!loc.latitude.isFinite || !loc.longitude.isFinite) {
              return;
            }
            final camera = _mapController.camera;
            _mapController.move(loc.toLatLng(), camera.zoom);
          },
        ),
      ],
      child: BlocBuilder<MapBloc, MapState>(
        // Everything below (the map, its layers, the FABs) must NOT rebuild
        // on the 1s elapsedTime tick — only the ActivityStatsWidget overlay
        // needs that cadence, and it's wrapped in its own nested BlocBuilder
        // further down. Without this, the whole FlutterMap subtree (vector
        // tile layer, polyline remapped from every point, km milestones
        // recomputed from scratch) rebuilt every second during a
        // recording — the one workload that must stay smooth and
        // battery-light for potentially hours. See H4 in
        // REVIEW-2026-07-FULL-APP.md. Every MapState field except
        // elapsedTime is listed explicitly (rather than excluding just
        // elapsedTime) so a future field addition doesn't silently start
        // being ignored here.
        buildWhen: (previous, current) =>
            previous.style != current.style ||
            previous.userLocation != current.userLocation ||
            previous.searchCenter != current.searchCenter ||
            previous.error != current.error ||
            previous.traces != current.traces ||
            previous.loadingStatus != current.loadingStatus ||
            previous.activity != current.activity ||
            previous.isPaused != current.isPaused ||
            previous.isFollowingUser != current.isFollowingUser ||
            previous.trackingGap != current.trackingGap,
        builder: (context, state) {
          // Treat a non-finite userLocation as if it weren't there at all.
          // LocationRepository drops these at source, but if any path ever
          // lets a NaN through, passing it as initialCenter sets the map
          // camera to LatLng(NaN,NaN) and every subsequent gesture throws.
          final loc = state.userLocation;
          final hasFiniteLocation =
              loc != null && loc.latitude.isFinite && loc.longitude.isFinite;
          // Wait for a location to centre on. A null style only blocks while
          // the tile config is still loading; once init has finished with no
          // style (keyless FOSS build) we render a functional tileless map.
          final stillLoadingStyle =
              state.style == null && state.loadingStatus != null;
          if (!hasFiniteLocation || stillLoadingStyle) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  if (state.loadingStatus != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _loadingMessage(
                        AppLocalizations.of(context),
                        state.loadingStatus!,
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ],
              ),
            );
          }

          return Scaffold(
            body: Stack(
              children: [
                Container(
                  color: AppColors.tertiary.background,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: state.userLocation!.toLatLng(),
                      initialZoom: Global.defaultZoom,
                      maxZoom: Global.maxZoom,
                      onPositionChanged: (position, hasGesture) {
                        if (hasGesture && state.isFollowingUser) {
                          bloc.add(const StopFollowingUser());
                        }
                      },
                    ),
                    children: [
                      if (state.style != null)
                        VectorTileLayer(
                          maximumZoom: Global.maxZoom,
                          theme: state.style!.theme,
                          tileProviders: state.style!.providers,
                          sprites: state.style!.sprites,
                        ),
                      if (state.traces.isNotEmpty)
                        _buildTracesLayer(state.traces),
                      if (state.activity != null &&
                          state.activity!.points.isNotEmpty) ...[
                        state.activity!.toPolylineLayer(),
                        KmMilestonesLayer(activity: state.activity!),
                      ],
                      // Animated pulse marker + heading indicator + accuracy
                      // circle. Deliberately uses its own internal geolocator
                      // subscription (no distance filter) for smooth visuals,
                      // separate from MapBloc's filtered stream used for
                      // activity scoring.
                      CurrentLocationLayer(
                        style: LocationMarkerStyle(
                          marker: DefaultLocationMarker(
                            color: AppColors.primary.background,
                            child: Icon(
                              Icons.navigation_rounded,
                              color: AppColors.primary.foreground,
                              size: 18,
                            ),
                          ),
                          markerSize: const Size.square(36),
                          markerDirection: MarkerDirection.heading,
                          accuracyCircleColor: AppColors.primary.background
                              .withAlpha(40),
                          headingSectorColor: AppColors.primary.background
                              .withAlpha(80),
                          headingSectorRadius: 64,
                        ),
                      ),
                      if (state.searchCenter != null &&
                          state.loadingStatus == LoadingStatus.loadingTraces)
                        _buildSquareOverlay(),
                      // Tile attribution is legally required when tiles are
                      // shown: the basemap is Protomaps rendering OpenStreetMap
                      // data (ODbL §4.3 and Protomaps' ToS both require visible
                      // credit). Omitted on the keyless tileless map.
                      if (state.style != null)
                        RichAttributionWidget(
                          alignment: AttributionAlignment.bottomLeft,
                          attributions: [
                            TextSourceAttribution(
                              'OpenStreetMap',
                              onTap: () => launchUrl(
                                Uri.parse(
                                  'https://www.openstreetmap.org/copyright',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                            TextSourceAttribution(
                              'Protomaps',
                              onTap: () => launchUrl(
                                Uri.parse('https://protomaps.com'),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (state.loadingStatus != null &&
                    state.loadingStatus != LoadingStatus.startingActivity)
                  const Center(child: CircularProgressIndicator()),
                if (state.activity != null)
                  Positioned(
                    top: 50,
                    left: 0,
                    right: 0,
                    // Nested BlocBuilder so the 1s elapsedTime tick only
                    // rebuilds this small overlay, not the map subtree above
                    // (gated out of the outer builder's buildWhen).
                    child: BlocBuilder<MapBloc, MapState>(
                      buildWhen: (previous, current) =>
                          previous.elapsedTime != current.elapsedTime ||
                          previous.activity != current.activity,
                      builder: (context, innerState) => ActivityStatsWidget(
                        activity: innerState.activity!,
                        elapsedTime: innerState.elapsedTime,
                        opaqueBackground: true,
                      ),
                    ),
                  ),
              ],
            ),
            floatingActionButton: SizedBox(
              width: _kFloatingActionButtonWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // FloatingActionButton.extended(
                  //   heroTag: 'search',
                  //   onPressed: () {
                  //     final center = _mapController.camera.center;
                  //     bloc.add(FetchTraces(center: center));
                  //   },
                  //   label: const Text('Search'),
                  //   icon: const Icon(Icons.search),
                  // ),
                  if (state.isPaused && state.activity != null) ...[
                    HoldToConfirmButton(
                      icon: Icons.stop_rounded,
                      label: AppLocalizations.of(context).btnStop,
                      shortTapHint: AppLocalizations.of(context).mapStopHint,
                      backgroundColor: AppColors.destructive.background,
                      foregroundColor: AppColors.destructive.foreground,
                      onConfirmed: () => bloc.add(const CeaseActivity()),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FloatingActionButton.extended(
                    onPressed: () {
                      if (state.userLocation == null) return;

                      _mapController.move(
                        state.userLocation!.toLatLng(),
                        Global.maxZoom,
                      );
                      bloc.add(const ToggleFollowUser());
                    },
                    backgroundColor: state.isFollowingUser
                        ? AppColors.secondary.background
                        : null,
                    label: Text(AppLocalizations.of(context).btnFollow),
                    icon: Icon(
                      Icons.my_location_rounded,
                      color: state.isFollowingUser
                          ? AppColors.secondary.foreground
                          : null,
                    ),
                  ),

                  if (state.activity != null) ...[
                    const SizedBox(height: 16),
                    FloatingActionButton.extended(
                      heroTag: 'pause',
                      onPressed: () => bloc.add(const PauseActivity()),
                      backgroundColor: AppColors.primary.background,
                      label: state.isPaused
                          ? Text(AppLocalizations.of(context).btnResume)
                          : Text(AppLocalizations.of(context).btnPause),
                      icon: state.isPaused
                          ? const Icon(Icons.play_arrow_rounded)
                          : const Icon(Icons.pause_rounded),
                    ),
                  ],

                  if (state.activity == null) ...[
                    const SizedBox(height: 16),
                    FloatingActionButton.extended(
                      heroTag: 'start',
                      onPressed:
                          state.loadingStatus == LoadingStatus.startingActivity
                          ? null
                          : () => bloc.add(const StartActivity()),
                      label:
                          state.loadingStatus == LoadingStatus.startingActivity
                          ? Text(AppLocalizations.of(context).btnStarting)
                          : Text(AppLocalizations.of(context).btnStart),
                      icon:
                          state.loadingStatus == LoadingStatus.startingActivity
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                // strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Map<List<LatLng>, int> _groupSegmentsByIntensity(List<TraceEntity> traces) {
    final Map<String, int> segmentCounts = {};
    final Map<String, List<LatLng>> segmentKeys = {};
    for (final trace in traces) {
      for (var i = 0; i < trace.points.length - 1; i++) {
        final pa = trace.points[i];
        final pb = trace.points[i + 1];
        // Public GPX traces from OSM can carry junk fixes — LatLng throws
        // on non-finite values, which would crash the whole map tree.
        if (!pa.latitude.isFinite ||
            !pa.longitude.isFinite ||
            !pb.latitude.isFinite ||
            !pb.longitude.isFinite) {
          continue;
        }
        final a = LatLng(pa.latitude, pa.longitude);
        final b = LatLng(pb.latitude, pb.longitude);
        final key = _segmentKey(a, b);
        segmentCounts[key] = (segmentCounts[key] ?? 0) + 1;
        segmentKeys[key] = [a, b];
      }
    }
    final Map<List<LatLng>, int> result = {};
    for (final entry in segmentCounts.entries) {
      result[segmentKeys[entry.key]!] = entry.value;
    }
    return result;
  }

  String _segmentKey(LatLng a, LatLng b) {
    final points = [
      '${a.latitude},${a.longitude}',
      '${b.latitude},${b.longitude}',
    ]..sort();
    return points.join('|');
  }

  Widget _buildTracesLayer(List<TraceEntity> traces) {
    final segments = _groupSegmentsByIntensity(traces);
    int maxIntensity = 1;
    if (segments.isNotEmpty) {
      maxIntensity = segments.values.reduce((a, b) => a > b ? a : b);
    }
    return PolylineLayer(
      polylines: segments.entries.map((entry) {
        final intensity = entry.value;
        final color = Color.lerp(
          Colors.red.withAlpha(30),
          Colors.red,
          intensity / maxIntensity,
        )!;
        return Polyline(
          points: entry.key,
          color: color,
          strokeWidth: 3.0 + (intensity - 1) * 2.0,
        );
      }).toList(),
    );
  }

  Widget _buildSquareOverlay() {
    final center = _mapController.camera.center;
    final bounds = _calculateBounds(center);

    return PolygonLayer(
      polygons: [
        Polygon(
          points: [
            LatLng(bounds.north, bounds.west),
            LatLng(bounds.north, bounds.east),
            LatLng(bounds.south, bounds.east),
            LatLng(bounds.south, bounds.west),
          ],
          color: AppColors.primary.background.withAlpha(10),
          borderColor: AppColors.secondary.background,
          borderStrokeWidth: 2.0,
        ),
      ],
    );
  }

  ({double north, double south, double east, double west}) _calculateBounds(
    LatLng center,
  ) {
    return (
      north: center.latitude + kSearchHalfSideDegrees,
      south: center.latitude - kSearchHalfSideDegrees,
      east: center.longitude + kSearchHalfSideDegrees,
      west: center.longitude - kSearchHalfSideDegrees,
    );
  }
}
