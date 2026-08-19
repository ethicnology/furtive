import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/map/map_view.dart';
import 'package:furtive/core/map/maplibre_map_view.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/core/widgets/activity_stats_widget.dart';
import 'package:furtive/core/widgets/activity_type_picker.dart';
import 'package:furtive/core/widgets/hold_to_confirm_button.dart';
import 'package:furtive/core/global.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/map_navigation.dart';
import 'package:furtive/features/map/pages/map_page_logic.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';
import 'package:furtive/features/recording/bloc/recording_state.dart';
import 'package:furtive/features/share/live_share_cubit.dart';
import 'package:furtive/features/activities/bloc/activities_bloc.dart';
import 'package:furtive/features/activities/bloc/activities_event.dart';
import 'package:furtive/features/activities/pages/activity_detail_page.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

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

  Future<void> _shareLiveLink(
    BuildContext context,
    LiveShareCubit sharing, {
    String? password,
  }) async {
    try {
      final link =
          sharing.state.link ?? await sharing.start(password: password);
      await SharePlus.instance.share(ShareParams(text: link));
    } catch (error) {
      if (!context.mounted) return;
      _showSnackBar(
        context,
        SnackBar(
          content: Text(AppLocalizations.of(context).shareFailed('$error')),
          backgroundColor: kDestructive,
        ),
      );
    }
  }

  /// Shared by both layouts: the control is reachable whether or not a
  /// recording is running, since a share can be armed in advance. Only one of
  /// the two branches is ever mounted, so the hero tag stays unique.
  Widget _liveShareFab(BuildContext context, AppLocalizations l10n) {
    return BlocBuilder<LiveShareCubit, LiveShareState>(
      builder: (context, share) {
        final sharing = context.read<LiveShareCubit>();
        return FloatingActionButton.extended(
          heroTag: 'live-share',
          onPressed: share.isStarting
              ? null
              : () => _showLiveShareActions(context, sharing),
          backgroundColor: share.isActive
              ? kMint
              : AppColors.secondary.background,
          foregroundColor: share.isActive
              ? Colors.black
              : AppColors.secondary.foreground,
          icon: Icon(
            share.isActive
                ? Icons.share_location_rounded
                : Icons.share_location_outlined,
          ),
          label: Text(
            share.isActive
                ? '${share.connectedRelays}/${share.totalRelays}'
                : l10n.liveShareButton,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Future<void> _showLiveShareActions(
    BuildContext context,
    LiveShareCubit sharing,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (!sharing.state.isActive) {
      final passwordController = TextEditingController();
      final start = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.liveShareTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.liveSharePasswordHelp),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l10n.liveSharePassword,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.btnCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.shareTooltip),
            ),
          ],
        ),
      );
      final password = passwordController.text;
      passwordController.dispose();
      if (!context.mounted || start != true) return;
      await _shareLiveLink(
        context,
        sharing,
        password: password.isEmpty ? null : password,
      );
      return;
    }
    final action = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.liveShareTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.btnStop),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.shareTooltip),
          ),
        ],
      ),
    );
    if (!context.mounted || action == null) return;
    if (action) {
      await _shareLiveLink(context, sharing);
    } else {
      await sharing.stop();
    }
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
        BlocListener<LiveShareCubit, LiveShareState>(
          listenWhen: (previous, current) =>
              previous.error != current.error && current.error != null,
          listener: (context, state) {
            _showSnackBar(
              context,
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).shareFailed(state.error!),
                ),
                backgroundColor: kDestructive,
              ),
            );
            context.read<LiveShareCubit>().clearError();
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
          listenWhen: shouldMoveToLocation,
          listener: (context, state) {
            final loc = state.userLocation!;
            if (!loc.latitude.isFinite || !loc.longitude.isFinite) return;
            // The first fix should leave the neutral world view and centre at a
            // useful zoom. Later fixes preserve the user's zoom, but only while
            // follow-mode is active.
            _mapView.moveTo(
              loc,
              state.isFollowingUser
                  ? _mapView.currentZoom ?? Global.defaultZoom
                  : Global.defaultZoom,
            );
          },
        ),
      ],
      child: BlocBuilder<MapBloc, MapState>(
        // The map subtree (vector tile layer, polylines, km milestones) must not
        // rebuild on the 1 s elapsed tick. Splitting the recording state into its
        // own bloc makes that structural rather than a buildWhen allowlist: the
        // tick now only ever touches RecordingState, which this builder does not
        // watch at all.
        // Anything this subtree renders has to be listed here. The two
        // recording-preference fields below were missing at first and the bug
        // hid itself: a GPS fix updates userLocation every couple of seconds,
        // so the picker label and the control side did rebuild — just not
        // because of their own change. On a stationary phone, or with the
        // stream still warming up, flipping the setting did nothing.
        buildWhen: (previous, current) =>
            previous.styleUrl != current.styleUrl ||
            previous.userLocation != current.userLocation ||
            previous.loadingStatus != current.loadingStatus ||
            previous.isFollowingUser != current.isFollowingUser ||
            previous.mapControlsOnLeft != current.mapControlsOnLeft ||
            previous.selectedActivityType != current.selectedActivityType ||
            previous.deviceHeading != current.deviceHeading,
        builder: (context, state) {
          // Treat a non-finite userLocation as if it weren't there at all.
          // LocationRepository drops these at source, but if any path ever lets a
          // NaN through, passing it as initialCenter sets the camera to
          // LatLng(NaN,NaN) and every subsequent gesture throws.
          final rawLoc = state.userLocation;
          final loc =
              rawLoc != null &&
                  rawLoc.latitude.isFinite &&
                  rawLoc.longitude.isFinite
              ? rawLoc
              : null;
          // A null style only blocks while the tile config is still loading;
          // once init has finished with no style (keyless FOSS build), render a
          // functional tileless map. A GPS fix is not a prerequisite: show a
          // neutral world view instead of an endless spinner, then centre on the
          // first valid fix when it arrives.
          if (!shouldRenderMap(state)) {
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
                        initialCentre: loc,
                        initialZoom: loc == null ? 1 : Global.defaultZoom,
                        maxZoom: Global.maxZoom,
                        showUserLocation: true,
                        // The same value the Follow button centres on, so the
                        // puck and the camera cannot point at different
                        // places.
                        userPosition: loc,
                        deviceHeading: state.deviceHeading,
                        controlsOnLeft: state.mapControlsOnLeft,
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
            // Mirrored for left-handed users. Every control that gets touched
            // mid-activity lives in this column, one-handed and often while
            // moving, so which thumb reaches it is not cosmetic.
            floatingActionButtonLocation: state.mapControlsOnLeft
                ? FloatingActionButtonLocation.startFloat
                : FloatingActionButtonLocation.endFloat,
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
                        if (context.read<LiveShareCubit>().isConfigured) ...[
                          const SizedBox(height: 16),
                          _liveShareFab(context, l10n),
                        ],
                      ],
                      if (!rec.isRecording) ...[
                        const SizedBox(height: 16),
                        // What the next recording will be. Shown rather than
                        // buried in settings because it changes how the GPS is
                        // sampled and filtered, and because the choice is only
                        // ever meaningful right before starting.
                        FloatingActionButton.extended(
                          heroTag: 'activity-type',
                          backgroundColor: AppColors.tertiary.background,
                          foregroundColor: AppColors.tertiary.foreground,
                          onPressed: rec.isStarting
                              ? null
                              : () async {
                                  final picked = await showActivityTypePicker(
                                    context,
                                    selected: state.selectedActivityType,
                                  );
                                  if (picked == null) return;
                                  map.add(SelectActivityType(picked));
                                },
                          icon: Icon(
                            activityTypeIcon(state.selectedActivityType),
                          ),
                          label: Text(
                            activityTypeName(l10n, state.selectedActivityType),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Above Start, not below: a share can be armed before
                        // the recording exists, but Start stays the last thing
                        // under the thumb.
                        if (context.read<LiveShareCubit>().isConfigured) ...[
                          const SizedBox(height: 16),
                          _liveShareFab(context, l10n),
                        ],
                        const SizedBox(height: 16),
                        FloatingActionButton.extended(
                          heroTag: 'start',
                          onPressed: rec.isStarting
                              ? null
                              : () => recording.add(
                                  StartRecording(
                                    activityType: state.selectedActivityType,
                                  ),
                                ),
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
