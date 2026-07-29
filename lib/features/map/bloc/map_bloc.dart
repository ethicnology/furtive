import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/repositories/location_repository.dart';
import 'package:furtive/core/usecases/get_map_style_url_use_case.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/features/map/position_stream_controller.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';

// Localised display strings live in MapPage (_loadingMessage); this enum is
// just the state tag.
enum LoadingStatus { localizing, loadingMap }

/// Map presentation only: the tile style, the live user location, and the
/// follow-camera toggle.
///
/// The recording state machine moved to [RecordingBloc] and the GPS stream
/// lifecycle to [PositionStreamController]. This bloc wires the two together —
/// it forwards each fix to the recorder and reports stream stalls — but owns
/// neither.
class MapBloc extends Bloc<MapEvent, MapState> with WidgetsBindingObserver {
  MapBloc({
    required RecordingBloc recording,
    GetMapStyleUrlUseCase? getMapStyleUrl,
    LocationRepository? location,
    PositionStreamController? positionStream,
  }) : this._(
         recording: recording,
         getMapStyleUrl: getMapStyleUrl ?? GetMapStyleUrlUseCase(),
         // Resolved ONCE and shared with the stream controller below. Writing
         // `location ?? LocationRepository()` in both initialisers built two
         // independent repositories — each with its own LocationGpsDataSource —
         // where one was intended.
         location: location ?? LocationRepository(),
         positionStream: positionStream,
       );

  MapBloc._({
    required RecordingBloc recording,
    required GetMapStyleUrlUseCase getMapStyleUrl,
    required LocationRepository location,
    required PositionStreamController? positionStream,
  }) : _recording = recording,
       _getMapStyleUrlUseCase = getMapStyleUrl,
       _location = location,
       _positions =
           positionStream ?? PositionStreamController(location: location),
       super(const MapState()) {
    on<InitMap>(_onInitMap);
    on<EnsureTracking>(_onEnsureTracking);
    on<ClearError>((_, emit) => emit(state.copyWith(error: null)));
    on<UpdateUserLocation>(_onUpdateUserLocation);
    on<ToggleFollowUser>(
      (_, emit) =>
          emit(state.copyWith(isFollowingUser: !state.isFollowingUser)),
    );
    on<StopFollowingUser>(
      (_, emit) => emit(state.copyWith(isFollowingUser: false)),
    );

    _positions.onPosition = (position) {
      if (!isClosed) add(UpdateUserLocation(position: position));
    };
    // A closed stream is NOT treated as "stop the activity": the notification is
    // ongoing (non-swipeable) and the service holds a wake lock, so a close means
    // the foreground service actually died rather than a user gesture. Ceasing
    // would silently end a run the user still wants.
    _positions.onStreamClosed = () {
      if (!isClosed) add(const InitMap());
    };

    // Observe app lifecycle so the stream is re-validated when the user returns.
    WidgetsBinding.instance.addObserver(this);

    // InitMap is NOT auto-fired: it triggers the OS location-permission dialog,
    // and this bloc is constructed at app start — before the onboarding wizard's
    // permissions step. MapPage.initState and OnboardingPage._finish fire it
    // explicitly once the user is ready to see the map.
  }

  final RecordingBloc _recording;
  final GetMapStyleUrlUseCase _getMapStyleUrlUseCase;
  final LocationRepository _location;
  final PositionStreamController _positions;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) add(const EnsureTracking());
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _positions.dispose();
    return super.close();
  }

  void _onUpdateUserLocation(UpdateUserLocation event, Emitter<MapState> emit) {
    final recordingState = _recording.state;
    final activity = recordingState.activity;
    if (activity != null) {
      final tuning = activity.activityType.movementProfile.tuning;
      final accurateEnough = tuning.acceptsAccuracy(event.position.accuracy);
      // The map stream deliberately admits one vague fix after a sustained
      // bad-signal spell so the cursor degrades instead of freezing. That is a
      // presentation policy, not permission to inflate the active trace.
      // Paused points remain writable even when vague: they establish the
      // active<->paused segment boundary and never contribute to distance.
      if (recordingState.isPaused || accurateEnough) {
        _recording.add(ScoreFix(position: event.position));
      } else {
        logs.warning(
          'MapBloc skipped an active fix outside the ${tuning.accuracyToleranceMeters.toStringAsFixed(0)} m '
          'recording tolerance (accuracy '
          '${event.position.accuracy?.toStringAsFixed(1) ?? 'unknown'} m).',
        );
      }
    }
    emit(state.copyWith(userLocation: event.position));
  }

  Future<void> _onInitMap(InitMap event, Emitter<MapState> emit) async {
    emit(state.copyWith(loadingStatus: LoadingStatus.localizing));

    // Isolated try/catch so a failure here can never prevent the resume or the
    // style load below from running — a single unguarded await used to be able
    // to strand an ongoing activity until it got auto-ceased.
    try {
      await _positions.ensureOpen();
    } catch (e, s) {
      logs.severe('InitMap openPositionStream', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    }

    // A cold start may follow an OS kill mid-recording (Doze / OEM battery
    // killer while locked). The activity and its points are still in the
    // database; rehydrate the run rather than losing it to a later auto-cease.
    //
    // Runs BEFORE the one-shot fix below: that fix can hang or throw right after
    // an unlock (GPS not warmed up), and doing the resume first makes it
    // independent of the fix's outcome. RecordingBloc's own `activity != null`
    // guard makes a repeat cheap.
    _recording.add(const ResumeOngoingRecording());

    try {
      emit(state.copyWith(userLocation: await _location.getCurrentLocation()));
    } catch (e, s) {
      // Non-fatal and deliberately silent (no error banner): right after a cold
      // start the GPS may simply not be warmed up. The already-open stream will
      // deliver a fix and update userLocation as soon as one arrives.
      logs.severe('InitMap getUserLocation', error: e, trace: s);
    }

    emit(state.copyWith(loadingStatus: LoadingStatus.loadingMap));
    try {
      final styleUrl = await _getMapStyleUrlUseCase();
      logs.info(
        'InitMap getStyleUrl: style '
        '${styleUrl == null ? 'null (tileless)' : 'resolved'}',
      );
      emit(state.copyWith(styleUrl: styleUrl));
    } catch (e, s) {
      logs.severe('InitMap getStyleUrl', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(loadingStatus: null));
    }
  }

  /// App returned to the foreground. If the stream died or went silent in the
  /// background (geolocator can suspend it in deep Doze without emitting
  /// onDone), reopen it — whether or not a recording is running. Returning early
  /// when nothing was being recorded meant a stream the OS killed while idle
  /// never got reopened for the rest of the session, leaving the live location
  /// frozen until an app restart.
  Future<void> _onEnsureTracking(
    EnsureTracking event,
    Emitter<MapState> emit,
  ) async {
    final gap = _positions.sinceLastFix;
    if (_positions.isOpen && !_positions.isStale) {
      // Logged so resume checks stay visible in the exported logs, distinct from
      // silence meaning "the app was never backgrounded".
      logs.fine('EnsureTracking: stream healthy, no reopen needed.');
      return;
    }

    // A stale stream while actively recording means the OS suspended or killed
    // the foreground service and no fixes were recorded for the gap — a hole the
    // reopen cannot backfill. Surface it so the user knows a segment is missing.
    // Only genuinely significant gaps (not first-open jitter), and only while
    // there is a recording to lose data from.
    if (_recording.state.isRecording &&
        !_recording.state.isPaused &&
        gap != null &&
        gap > PositionStreamController.staleThreshold) {
      logs.warning(
        'EnsureTracking: tracking gap of ${gap.inSeconds}s detected '
        '(stream suspended/killed while backgrounded).',
      );
      _recording.add(ReportTrackingGap(gap));
    }

    logs.warning('EnsureTracking: position stream stale/dead, reopening.');
    try {
      await _positions.reopen();
      logs.info('EnsureTracking: position stream reopened successfully.');
    } catch (e, s) {
      logs.severe('EnsureTracking reopen', error: e, trace: s);
    }
  }
}
