import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/map/map_view.dart';
import 'package:furtive/core/map/maplibre_map_view.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/activity_stats_widget.dart';
import 'package:furtive/core/widgets/hold_to_confirm_button.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/map_navigation.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';
import 'package:furtive/features/recording/bloc/recording_state.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:furtive/features/activities/pages/activity_detail_page.dart';
import 'package:furtive/l10n/app_localizations.dart';

String _loadingMessage(AppLocalizations l10n, LoadingStatus status) =>
    switch (status) {
      LoadingStatus.localizing => l10n.mapLoadingLocalizing,
      LoadingStatus.loadingMap => l10n.mapLoadingMap,
    };

class MapPage extends StatefulWidget {
  const MapPage({super.key, this.selectedTab});

  /// Selected page in BottomNavigationWidget's PageView. Null when MapPage is
  /// hosted standalone (tests or a future dedicated route), where it is visible.
  final ValueListenable<int>? selectedTab;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with AutomaticKeepAliveClientMixin {
  final MapView _mapView = MapLibreMapView();
  static const _kFloatingActionButtonWidth = 115.0;

  // Stay alive across BottomNavigation tab switches so the stop -> stats
  // listener keeps firing even when the user is on Activities or Settings.
  @override
  bool get wantKeepAlive => true;

  StreamSubscription<RecordingState>? _stopSub;

  @override
  void initState() {
    super.initState();
    final map = context.read<MapBloc>();
    final recording = context.read<RecordingBloc>();

    // Trigger location/map init the first time the page mounts. Safe to call
    // repeatedly — InitMap leaves an already-open position stream untouched
    // (reopening would drop in-flight fixes) and PositionStreamController guards
    // concurrent opens — but AutomaticKeepAliveClientMixin keeps this State
    // alive across tab switches, so it fires once per cold start. The onboarded
    // cold-start path lands here; the wizard-finish path fires InitMap
    // explicitly before navigating.
    if (map.state.styleUrl == null) map.add(const InitMap());

    // Route to the activity detail page when the running activity ends (the
    // user holds Stop). The previous activity is tracked manually because
    // BlocListener's listener cannot see the pre-transition state and a
    // side-effecting listenWhen is fragile.
    ActivityEntity? previous = recording.state.activity;
    _stopSub = recording.stream.listen((state) {
      final ceased = previous;
      if (ceased != null && state.activity == null && mounted) {
        context.read<ActivitiesBloc>().add(const FetchActivities());
        // Only push when this page's route is actually on top. The State is kept
        // alive across tab switches, so route state alone is insufficient: all
        // three PageView children share the same ModalRoute.
        if (shouldOpenStoppedActivity(
          routeIsCurrent: ModalRoute.of(context)?.isCurrent ?? false,
          selectedTab: widget.selectedTab?.value ?? 0,
        )) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ActivityDetailPage(activity: ceased),
            ),
          );
        }
      }
      previous = state.activity;
    });
  }

  @override
  void dispose() {
    _stopSub?.cancel();
    unawaited(_mapView.dispose());
    super.dispose();
  }

  /// Replaces any snackbar already on screen instead of queueing behind it.
  /// Several independent listeners here can fire in the same frame (an error, a
  /// tracking gap, a start confirmation); without this they stack up and the
  /// user dismisses a queue.
  void _showSnackBar(BuildContext context, SnackBar bar) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(bar);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final map = context.read<MapBloc>();
    final recording = context.read<RecordingBloc>();

    return MultiBlocListener(
      listeners: [
        BlocListener<MapBloc, MapState>(
          listenWhen: (previous, current) => previous.error != current.error,
          listener: (context, state) {
            if (state.error == null) return;
            _showSnackBar(
              context,
              SnackBar(
                content: Text(state.error!.message),
                backgroundColor: kDestructive,
                duration: const Duration(seconds: 3),
              ),
            );
            context.read<MapBloc>().add(const ClearError());
          },
        ),
        BlocListener<RecordingBloc, RecordingState>(
          listenWhen: (previous, current) => previous.error != current.error,
          listener: (context, state) {
            if (state.error == null) return;
            _showSnackBar(
              context,
              SnackBar(
                content: Text(state.error!.message),
                backgroundColor: kDestructive,
                duration: const Duration(seconds: 3),
              ),
            );
            context.read<RecordingBloc>().add(const ClearRecordingError());
          },
        ),
        BlocListener<RecordingBloc, RecordingState>(
          listenWhen: (previous, current) =>
              previous.trackingGap != current.trackingGap &&
              current.trackingGap != null,
          listener: (context, state) {
            _showSnackBar(
              context,
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  ).mapTrackingGapMsg(state.trackingGap!.inSeconds),
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: Theme.of(context).textTheme.bodyMedium?.fontSize,
                  ),
                ),
                backgroundColor: kWarning,
                duration: const Duration(seconds: 6),
              ),
            );
            context.read<RecordingBloc>().add(const ClearTrackingGap());
          },
        ),
        BlocListener<RecordingBloc, RecordingState>(
          // `current.activity != null` excludes the failure path: on a failed
          // start the catch emits an error and the finally clears isStarting
          // WITHOUT an activity ever being set — without this check that
          // transition matched too and showed a big "Activity started" toast on
          // top of the error snackbar.
          listenWhen: (previous, current) =>
              previous.isStarting &&
              !current.isStarting &&
              current.activity != null,
          listener: (context, state) {
            final screenSize = MediaQuery.sizeOf(context);
            _showSnackBar(
              context,
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).mapActivityStartedMsg,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                margin: EdgeInsets.only(
                  bottom: screenSize.height * 0.25,
                  left: screenSize.width * 0.1,
                  right: screenSize.width * 0.1,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 24,
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        BlocListener<RecordingBloc, RecordingState>(
          // Fire ONLY on a fresh start: an activity that already existed with no
          // points just got its first one. Requiring previous.activity non-null
          // deliberately excludes the cold-start resume path (where the activity
          // appears already populated) — resuming must NOT call
          // _mapController.move, because the resumed activity is emitted while
          // the map is still loading/unmounted and move() throws on an unattached
          // controller. On resume the camera stays on the current location rather
          // than jumping to the old track start.
          listenWhen: (previous, current) =>
              previous.activity != null &&
              previous.activity!.points.isEmpty &&
              current.activity != null &&
              current.activity!.points.isNotEmpty,
          listener: (context, state) {
            final firstPoint = state.activity!.points.first;
            // Belt-and-suspenders: LocationRepository already drops non-finite
            // frames, but if anything ever lets a NaN through, calling
            // _mapController.move(LatLng(NaN,NaN)) poisons the camera and every
            // subsequent gesture/tile update throws.
            if (!firstPoint.position.latitude.isFinite ||
                !firstPoint.position.longitude.isFinite) {
              return;
            }
            _mapView.moveTo(firstPoint.position, Global.maxZoom);
          },
        ),
        BlocListener<MapBloc, MapState>(
          listenWhen: (previous, current) =>
              current.isFollowingUser &&
              current.userLocation != null &&
              previous.userLocation != current.userLocation,
          listener: (context, state) {
            final loc = state.userLocation!;
            if (!loc.latitude.isFinite || !loc.longitude.isFinite) return;
            // Keep whatever zoom the user chose; only the centre follows.
            _mapView.moveTo(loc, _mapView.currentZoom ?? Global.defaultZoom);
          },
        ),
      ],
      child: BlocBuilder<MapBloc, MapState>(
        // The map subtree (vector tile layer, polylines, km milestones) must not
        // rebuild on the 1 s elapsed tick. Splitting the recording state into its
        // own bloc makes that structural rather than a buildWhen allowlist: the
        // tick now only ever touches RecordingState, which this builder does not
        // watch at all.
        buildWhen: (previous, current) =>
            previous.styleUrl != current.styleUrl ||
            previous.userLocation != current.userLocation ||
            previous.loadingStatus != current.loadingStatus ||
            previous.isFollowingUser != current.isFollowingUser,
        builder: (context, state) {
          // Treat a non-finite userLocation as if it weren't there at all.
          // LocationRepository drops these at source, but if any path ever lets a
          // NaN through, passing it as initialCenter sets the camera to
          // LatLng(NaN,NaN) and every subsequent gesture throws.
          final loc = state.userLocation;
          final hasFiniteLocation =
              loc != null && loc.latitude.isFinite && loc.longitude.isFinite;
          // Wait for a location to centre on. A null style only blocks while the
          // tile config is still loading; once init has finished with no style
          // (keyless FOSS build) render a functional tileless map.
          final stillLoadingStyle =
              state.styleUrl == null && state.loadingStatus != null;
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
                      style: Theme.of(context).textTheme.titleMedium,
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
                  // The track sits behind its own builder so the 1 s elapsed
                  // tick never reaches the map. This is as deep as the isolation
                  // can go: MapLibre's layers are immutable value objects rather
                  // than widgets, so the track cannot be handed in by a builder
                  // nested inside the map itself. Cheap regardless — rebuilding
                  // does not recreate the native view, and the benchmark
                  // measured this exact path at ~2 ms/frame with no jank.
                  child: BlocBuilder<RecordingBloc, RecordingState>(
                    buildWhen: (previous, current) =>
                        previous.activity != current.activity,
                    builder: (context, rec) {
                      final activity = rec.activity;
                      return _mapView.build(
                        styleUrl: state.styleUrl,
                        track: activity == null || activity.points.isEmpty
                            ? null
                            : activity,
                        initialCentre: state.userLocation,
                        initialZoom: Global.defaultZoom,
                        maxZoom: Global.maxZoom,
                        showUserLocation: true,
                        // Panning by hand means the user wants to look somewhere
                        // else, so stop dragging the camera back.
                        onUserGesture: () {
                          if (state.isFollowingUser) {
                            map.add(const StopFollowingUser());
                          }
                        },
                      );
                    },
                  ),
                ),
                if (state.loadingStatus != null)
                  const Center(child: CircularProgressIndicator()),
                // Stats overlay: rebuilt by the 1 s tick, which is why it has its
                // own builder well away from the map subtree.
                BlocBuilder<RecordingBloc, RecordingState>(
                  buildWhen: (previous, current) =>
                      previous.elapsedTime != current.elapsedTime ||
                      previous.activity != current.activity,
                  builder: (context, rec) {
                    if (rec.activity == null) return const SizedBox.shrink();
                    return Positioned(
                      top: 50,
                      left: 0,
                      right: 0,
                      child: ActivityStatsWidget(
                        activity: rec.activity!,
                        elapsedTime: rec.elapsedTime,
                        opaqueBackground: true,
                      ),
                    );
                  },
                ),
              ],
            ),
            floatingActionButton: BlocBuilder<RecordingBloc, RecordingState>(
              buildWhen: (previous, current) =>
                  previous.isRecording != current.isRecording ||
                  previous.isPaused != current.isPaused ||
                  previous.isStarting != current.isStarting,
              builder: (context, rec) {
                final l10n = AppLocalizations.of(context);
                return SizedBox(
                  width: _kFloatingActionButtonWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rec.isPaused && rec.isRecording) ...[
                        HoldToConfirmButton(
                          icon: Icons.stop_rounded,
                          label: l10n.btnStop,
                          shortTapHint: l10n.mapStopHint,
                          backgroundColor: AppColors.destructive.background,
                          foregroundColor: AppColors.destructive.foreground,
                          onConfirmed: () =>
                              recording.add(const StopRecording()),
                        ),
                        const SizedBox(height: 16),
                      ],
                      FloatingActionButton.extended(
                        onPressed: () {
                          final current = map.state.userLocation;
                          if (current == null) return;
                          _mapView.moveTo(current, Global.maxZoom);
                          map.add(const ToggleFollowUser());
                        },
                        backgroundColor: state.isFollowingUser
                            ? AppColors.secondary.background
                            : null,
                        label: Text(l10n.btnFollow),
                        icon: Icon(
                          Icons.my_location_rounded,
                          color: state.isFollowingUser
                              ? AppColors.secondary.foreground
                              : null,
                        ),
                      ),
                      if (rec.isRecording) ...[
                        const SizedBox(height: 16),
                        FloatingActionButton.extended(
                          heroTag: 'pause',
                          onPressed: () =>
                              recording.add(const PauseRecording()),
                          backgroundColor: AppColors.primary.background,
                          label: Text(
                            rec.isPaused ? l10n.btnResume : l10n.btnPause,
                          ),
                          icon: Icon(
                            rec.isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                          ),
                        ),
                      ],
                      if (!rec.isRecording) ...[
                        const SizedBox(height: 16),
                        FloatingActionButton.extended(
                          heroTag: 'start',
                          onPressed: rec.isStarting
                              ? null
                              : () => recording.add(const StartRecording()),
                          label: Text(
                            rec.isStarting ? l10n.btnStarting : l10n.btnStart,
                          ),
                          icon: rec.isStarting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
