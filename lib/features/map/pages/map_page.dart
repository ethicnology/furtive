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
import 'package:vector_map_tiles/vector_map_tiles.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage>
    with AutomaticKeepAliveClientMixin {
  final _mapController = MapController();
  static const _kFloatingActionButtonWidth = 115.0;

  // Stay alive across BottomNavigation tab switches so the F6 cease →
  // stats listener keeps firing even when the user is on Activities or
  // Settings. Otherwise PageView disposes us and a watchdog cease while
  // off-tab would silently end the activity with no redirect.
  @override
  bool get wantKeepAlive => true;
  StreamSubscription<MapState>? _ceaseSub;

  @override
  void initState() {
    super.initState();
    // F6: route to the activity stats page when the running activity ends
    // (Stop tap, notification swipe, or watchdog cease). We track the
    // previous activity manually since BlocListener's listener can't see
    // the pre-transition state and side-effecting listenWhen is fragile.
    final bloc = context.read<MapBloc>();
    // Trigger location/map init the first time the page mounts. Safe to
    // call repeatedly — _onInitMap cancels any prior position stream — but
    // AutomaticKeepAliveClientMixin keeps this State alive across tab
    // switches so it only fires once per cold start. The onboarded
    // cold-start path lands here; the wizard-finish path fires InitMap
    // explicitly before navigating.
    if (bloc.state.style == null) bloc.add(const InitMap());
    ActivityEntity? prev = bloc.state.activity;
    _ceaseSub = bloc.stream.listen((state) {
      if (prev != null && state.activity == null) {
        final ceased = prev!;
        if (mounted) {
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
                  content: Text(
                    state.error!.message,
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
              context.read<MapBloc>().add(const ClearError());
            }
          },
        ),
        BlocListener<MapBloc, MapState>(
          listenWhen:
              (previous, current) =>
                  previous.loadingStatus == LoadingStatus.startingActivity &&
                  current.loadingStatus == null,
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
          listenWhen:
              (previous, current) =>
                  (previous.activity == null ||
                      previous.activity!.points.isEmpty) &&
                  current.activity != null &&
                  current.activity!.points.isNotEmpty,
          listener: (context, state) {
            final firstPoint = state.activity!.points.first;
            _mapController.move(firstPoint.position.toLatLng(), Global.maxZoom);
          },
        ),
        BlocListener<MapBloc, MapState>(
          listenWhen:
              (previous, current) =>
                  current.isFollowingUser &&
                  current.userLocation != null &&
                  previous.userLocation != current.userLocation,
          listener: (context, state) {
            final camera = _mapController.camera;
            _mapController.move(state.userLocation!.toLatLng(), camera.zoom);
          },
        ),
      ],
      child: BlocBuilder<MapBloc, MapState>(
        builder: (context, state) {
          if (state.style == null || state.userLocation == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  if (state.loadingStatus != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      state.loadingStatus!.message,
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
                              Icons.navigation,
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
                    child: ActivityStatsWidget(
                      activity: state.activity!,
                      elapsedTime: state.elapsedTime,
                      opaqueBackground: true,
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
                      icon: Icons.stop,
                      label: AppLocalizations.of(context).btnStop,
                      shortTapHint:
                          AppLocalizations.of(context).mapStopHint,
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
                    backgroundColor:
                        state.isFollowingUser
                            ? AppColors.secondary.background
                            : null,
                    label: Text(AppLocalizations.of(context).btnFollow),
                    icon: Icon(
                      Icons.my_location,
                      color:
                          state.isFollowingUser
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
                      label:
                          state.isPaused
                              ? Text(AppLocalizations.of(context).btnResume)
                              : Text(AppLocalizations.of(context).btnPause),
                      icon:
                          state.isPaused
                              ? const Icon(Icons.play_arrow)
                              : const Icon(Icons.pause),
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
                              ? Text(
                                AppLocalizations.of(context).btnStarting,
                              )
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
                              : const Icon(Icons.play_arrow),
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
      polylines:
          segments.entries.map((entry) {
            final intensity = entry.value;
            final color =
                Color.lerp(
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
