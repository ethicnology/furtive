import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/entities/activity_profile.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/facades/compass_facade.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/repositories/location_repository.dart';
import 'package:furtive/core/repositories/preferences_repository.dart';
import 'package:furtive/core/usecases/get_map_style_url_use_case.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/features/map/position_stream_controller.dart';
import 'package:furtive/features/recording/bloc/recording_bloc.dart';
import 'package:furtive/features/recording/bloc/recording_event.dart';
import 'package:furtive/features/recording/bloc/recording_state.dart';

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
    PreferencesRepository? preferences,
    CompassFacade? compass,
  }) : this._(
         recording: recording,
         getMapStyleUrl: getMapStyleUrl ?? GetMapStyleUrlUseCase(),
         compass: compass ?? CompassFacade(),
         // Resolved ONCE and shared with the stream controller below. Writing
         // `location ?? LocationRepository()` in both initialisers built two
         // independent repositories — each with its own LocationGpsDataSource —
         // where one was intended.
         location: location ?? LocationRepository(),
         positionStream: positionStream,
         preferences: preferences ?? PreferencesRepository(),
       );

  MapBloc._({
    required RecordingBloc recording,
    required GetMapStyleUrlUseCase getMapStyleUrl,
    required LocationRepository location,
    required PositionStreamController? positionStream,
    required PreferencesRepository preferences,
    required CompassFacade compass,
  }) : _recording = recording,
       _getMapStyleUrlUseCase = getMapStyleUrl,
       _location = location,
       _preferences = preferences,
       _compass = compass,
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
    on<SelectActivityType>(_onSelectActivityType);
    on<ApplyMovementProfile>(_onApplyMovementProfile);
    on<UpdateDeviceHeading>(
      (event, emit) => emit(state.copyWith(deviceHeading: event.degrees)),
      // The compass emits several times a second. Without this every sample
      // would queue a separate transition and rebuild the marker layer;
      // restartable keeps only the newest, which is the only one that
      // describes where the phone is pointing now.
      transformer: restartable(),
    );

    // No-op off Android and on devices without a rotation-vector sensor: the
    // stream is empty there and the puck falls back to course over ground.
    _compassSub = _compass.headings().listen(
      (degrees) {
        // Logged once, not per sample: "is the compass feeding the puck at
        // all" is the first question to ask when the cone does not appear, and
        // the answer is otherwise invisible from a log file.
        if (!_loggedFirstHeading) {
          _loggedFirstHeading = true;
          logs.info(
            'Compass: first heading ${degrees.toStringAsFixed(1)}° '
            '(supported: ${_compass.isSupported}).',
          );
        }
        if (!isClosed) add(UpdateDeviceHeading(degrees));
      },
      onDone: () => logs.warning(
        'Compass: stream closed — no device heading available, the puck falls '
        'back to course over ground.',
      ),
    );
    on<RefreshRecordingPreferences>(
      (_, emit) => _loadRecordingPreferences(emit),
    );

    // The recorded activity's type is what the GPS stream must follow, and it
    // can change through three different doors: the user starts a recording,
    // stops one, or the app cold-starts onto an activity the OS killed
    // mid-run. Watching the recorder covers all three with one path, instead
    // of asking every caller to remember to reconfigure the stream.
    _recordingSub = _recording.stream.listen((recordingState) {
      final profile = recordingState.activity?.activityType.movementProfile;
      if (profile == _appliedProfile) return;
      _appliedProfile = profile;
      if (!isClosed) add(ApplyMovementProfile(profile));
    });

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
  final PreferencesRepository _preferences;
  final CompassFacade _compass;
  StreamSubscription<RecordingState>? _recordingSub;
  StreamSubscription<double>? _compassSub;

  /// Last profile handed to the stream controller. Tracked here rather than
  /// read back from the controller so the subscription below stays a cheap
  /// equality check on every recording-state emission (one per GPS fix).
  MovementProfileEntity? _appliedProfile;
  bool _loggedFirstHeading = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) add(const EnsureTracking());
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _recordingSub?.cancel();
    // Cancelling unregisters the sensor listener on the platform side; left
    // running it keeps the sensor hub awake for the life of the process.
    await _compassSub?.cancel();
    await _positions.dispose();
    return super.close();
  }

  /// Pulls the recording preferences into state and pushes the sampling detail
  /// down to the stream controller. Shared by [InitMap] and
  /// [RefreshRecordingPreferences] so the two can never drift apart.
  Future<void> _loadRecordingPreferences(Emitter<MapState> emit) async {
    try {
      final preferences = await _preferences.fetch();
      emit(
        state.copyWith(
          selectedActivityType: preferences.lastActivityType,
          recordingDetail: preferences.recordingDetail,
          mapControlsOnLeft: preferences.mapControlsOnLeft,
        ),
      );
      // Keeps whatever profile is currently recording; only the detail can
      // have changed here.
      await _positions.applyProfile(
        profile: _appliedProfile,
        detail: preferences.recordingDetail,
      );
    } catch (e, s) {
      // Defaults in MapState are usable; a failed read must not stop the map
      // from loading.
      logs.severe('load recording preferences', error: e, trace: s);
    }
  }

  Future<void> _onSelectActivityType(
    SelectActivityType event,
    Emitter<MapState> emit,
  ) async {
    emit(state.copyWith(selectedActivityType: event.activityType));
    // Remembered immediately rather than on start, so the choice survives the
    // user changing their mind and closing the app without recording.
    try {
      final current = await _preferences.fetch();
      await _preferences.store(
        current.copyWith(lastActivityType: event.activityType),
      );
    } catch (e, s) {
      // A failed write must not block recording — the selection is already
      // live in state, it just won't be remembered next launch.
      logs.severe('SelectActivityType persist', error: e, trace: s);
    }
  }

  Future<void> _onApplyMovementProfile(
    ApplyMovementProfile event,
    Emitter<MapState> emit,
  ) async {
    try {
      await _positions.applyProfile(
        profile: event.profile,
        detail: state.recordingDetail,
      );
    } catch (e, s) {
      // Reopening the stream is where this can fail. The previous stream is
      // already gone, so surface the failure and immediately run the watchdog
      // once instead of silently recording no points until the next app resume.
      logs.severe('ApplyMovementProfile', error: e, trace: s);
      emit(state.copyWith(error: AppError(e.toString())));
      if (!isClosed) add(const EnsureTracking());
    }
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
    // Feeds the magnetic-to-true-north correction. Declination varies over
    // kilometres, so every fix is far more often than needed — but it is one
    // cheap platform call against a stream that already runs at seconds
    // apart, and it keeps the compass correct without a second trigger.
    unawaited(
      _compass.updatePosition(
        latitude: event.position.latitude,
        longitude: event.position.longitude,
        altitude: event.position.elevation,
      ),
    );
    emit(state.copyWith(userLocation: event.position));
  }

  Future<void> _onInitMap(InitMap event, Emitter<MapState> emit) async {
    emit(state.copyWith(loadingStatus: LoadingStatus.localizing));

    // Loaded BEFORE the stream is opened below, so the first open already uses
    // the right sampling detail instead of opening at the default and being
    // reopened a moment later.
    await _loadRecordingPreferences(emit);

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
        gap > _positions.staleThreshold) {
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
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }
}
