import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/usecases/get_user_location_use_case.dart';
import 'package:furtive/core/usecases/start_track_position_use_case.dart';
import 'package:furtive/core/usecases/score_activity_use_case.dart';
import 'package:furtive/core/usecases/start_activity_use_case.dart';
import 'package:furtive/core/usecases/cease_activity_use_case.dart';
import 'package:furtive/core/usecases/resume_ongoing_activity_use_case.dart';
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/core/usecases/get_map_tile_url_use_case.dart';
import 'package:furtive/core/usecases/get_traces_use_case.dart';
import 'package:furtive/features/map/error.dart';

const double kSearchHalfSideDegrees = 0.01425;

// Localised display strings live in MapPage (_loadingMessage); this enum is
// just the state tag.
enum LoadingStatus { localizing, loadingMap, loadingTraces, startingActivity }

class MapBloc extends Bloc<MapEvent, MapState> {
  final _getMapConfigUseCase = GetMapConfigUseCase();
  final _getPublicGpsTracesUseCase = GetTracesUseCase();
  final _beginActivityUseCase = StartActivityUseCase();
  final _scoreActivityUseCase = ScoreActivityUseCase();
  final _ceaseActivityUsecase = CeaseActivityUseCase();
  final _startTrackPositionUsecase = StartTrackPositionUseCase();
  final _getUserLocationUseCase = GetUserLocationUseCase();
  final _resumeOngoingActivityUseCase = ResumeOngoingActivityUseCase();

  StreamSubscription<PositionEntity>? _positionStream;
  Timer? _elapsedTimer;
  DateTime? _activityStartTime;
  DateTime? _pauseStartTime;
  Duration _totalPausedDuration = Duration.zero;

  MapBloc() : super(const MapState()) {
    on<InitMap>(_onInitMap);
    on<FetchTraces>(_onTracesSearchRequested);
    on<StartActivity>(_onStartActivity);
    on<CeaseActivity>(_onCeaseActivity);
    on<ScoreActivity>(_onScoreActivity);
    on<PauseActivity>(_onPauseActivity);
    on<ClearError>(_onClearError);
    on<UpdateElapsedTime>(_onUpdateElapsedTime);
    on<UpdateUserLocation>(_onUpdateUserLocation);
    on<ToggleFollowUser>(_onToggleFollowUser);
    on<StopFollowingUser>(_onStopFollowingUser);

    // InitMap is NOT auto-fired here — it triggers the OS location-permission
    // dialog, and the bloc is instantiated at app start (via the BlocProvider
    // in MyApp) which happens before the onboarding wizard's permissions
    // step. MapPage.initState and OnboardingPage._finish fire it explicitly
    // once the user is ready to see the map.
  }

  void _onUpdateUserLocation(UpdateUserLocation event, Emitter<MapState> emit) {
    try {
      if (state.activity != null) {
        add(ScoreActivity(position: event.position));
      }
      emit(state.copyWith(userLocation: event.position));
    } catch (e) {
      logs.severe('$UpdateUserLocation: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  @override
  Future<void> close() async {
    await _positionStream?.cancel();
    _elapsedTimer?.cancel();
    return super.close();
  }

  Future<void> _onInitMap(InitMap event, Emitter<MapState> emit) async {
    try {
      emit(state.copyWith(loadingStatus: LoadingStatus.localizing));

      // B38/H1: InitMap can re-fire — from the onboarding finish and from
      // PreferencesBloc on every theme/locale apply. Open the position stream
      // only once: if it's already running, leave it untouched so a preference
      // change mid-activity doesn't tear down live tracking (dropping fixes) or
      // leak a second listener. A re-init then just
      // refreshes the user location and map style below. A failed first
      // subscription leaves _positionStream null, so a later InitMap retries.
      final isColdOpen = _positionStream == null;
      if (isColdOpen) {
        final userPositionStream = await _startTrackPositionUsecase();
        _positionStream = userPositionStream
            .handleError((error) => logs.severe('error: $error'))
            .listen(
              (position) => add(UpdateUserLocation(position: position)),
              // The stream closing is NOT treated as "stop the activity" any
              // more. The notification is now ongoing (non-swipeable) and the
              // service holds a wake lock, so a close here means the
              // foreground service actually died (rare) — not a user gesture.
              // Ceasing on it would silently end a run the user still wants;
              // instead drop the dead subscription and re-init to reopen the
              // stream. The activity row stays open and keeps recording.
              onDone: () {
                logs.warning('Position stream closed; reopening.');
                _positionStream = null;
                add(const InitMap());
              },
            );
      }

      final userPosition = await _getUserLocationUseCase();
      emit(state.copyWith(userLocation: userPosition));

      // Cold start may follow an OS process kill that happened mid-recording
      // (Doze / OEM battery killer while the phone was locked). The activity
      // and its points are still in the DB; rehydrate the run so the user sees
      // their ongoing activity instead of a blank map. Runs only on the first
      // stream open, and only if no activity is already live in memory.
      //
      // MUST come AFTER the userLocation emit: emitting the resumed activity
      // (which carries points) flips MapPage's recenter listener, and that
      // listener calls MapController.move — which throws unless the FlutterMap
      // is mounted, and the map only mounts once userLocation is finite.
      if (isColdOpen) await _resumeOngoingActivity(emit);

      emit(state.copyWith(loadingStatus: LoadingStatus.loadingMap));
      final style = await _getMapConfigUseCase();
      emit(state.copyWith(style: style));
    } catch (e) {
      logs.severe('$InitMap: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(loadingStatus: null));
    }
  }

  // Restore an in-progress recording from the DB after a cold start. No-op if
  // an activity is already live (the bloc survived) or nothing is ongoing.
  Future<void> _resumeOngoingActivity(Emitter<MapState> emit) async {
    if (state.activity != null) return;
    try {
      final ongoing = await _resumeOngoingActivityUseCase();
      if (ongoing == null) return;

      // Rebuild the timing bookkeeping the in-memory bloc lost on the kill.
      // startedAt is authoritative; paused time is recomputed from the
      // persisted point statuses (same calc the stats use). We resume in the
      // running (not paused) state — the user can pause again if they want.
      _activityStartTime = ongoing.startedAt;
      _totalPausedDuration = ongoing.pausedDuration;
      _pauseStartTime = null;
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => add(const UpdateElapsedTime()),
      );

      final elapsed =
          DateTime.now().difference(_activityStartTime!) - _totalPausedDuration;
      logs.info('Resumed ongoing activity ${ongoing.id} from storage.');
      emit(
        state.copyWith(
          activity: ongoing,
          isPaused: false,
          elapsedTime: elapsed.isNegative ? Duration.zero : elapsed,
        ),
      );
    } catch (e) {
      // A failed resume must not block the map from loading.
      logs.severe('resumeOngoingActivity: $e');
    }
  }

  Future<void> _onStartActivity(
    StartActivity event,
    Emitter<MapState> emit,
  ) async {
    try {
      emit(state.copyWith(loadingStatus: LoadingStatus.startingActivity));

      _elapsedTimer?.cancel();
      _pauseStartTime = null;
      _totalPausedDuration = Duration.zero;

      // First we wait for user location
      final userPosition = await _getUserLocationUseCase();
      // Then we start the activity
      final activity = await _beginActivityUseCase();
      // Then add the current location to the activity
      add(UpdateUserLocation(position: userPosition));
      _activityStartTime = activity.startedAt;

      _elapsedTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => add(const UpdateElapsedTime()),
      );

      emit(state.copyWith(activity: activity));
    } catch (e) {
      logs.severe('$StartActivity: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(loadingStatus: null));
    }
  }

  Future<void> _onScoreActivity(
    ScoreActivity event,
    Emitter<MapState> emit,
  ) async {
    // A CeaseActivity (manual stop) can be processed between
    // _onUpdateUserLocation dispatching this event and the handler running,
    // nulling state.activity. Return rather than throwing —
    // the old `throw ActivityNotStartedError()` was outside the try/catch and
    // leaked an unhandled error into the bloc zone.
    final activity = state.activity;
    if (activity == null) return;
    final position = event.position;
    final status =
        state.isPaused
            ? ActivityPointStatusEntity.paused
            : ActivityPointStatusEntity.active;

    try {
      final newPoint = await _scoreActivityUseCase(
        activityId: activity.id,
        position: position,
        status: status,
      );
      // Append to the LATEST in-memory activity, not the pre-await capture:
      // concurrent ScoreActivity handlers would otherwise each append to the
      // same stale points list and clobber one another (a point vanishes from
      // the live polyline). If a cease landed during the await, skip the emit.
      final current = state.activity;
      if (current == null || current.id != activity.id) return;
      emit(
        state.copyWith(
          activity: current.copyWith(points: [...current.points, newPoint]),
        ),
      );
    } catch (e) {
      logs.severe('$ScoreActivity: $e');
      emit(state.copyWith(error: AppError('ScoreActivity: $e')));
    }
  }

  void _onPauseActivity(PauseActivity event, Emitter<MapState> emit) {
    try {
      if (state.activity == null) throw ActivityNotStartedError();

      final wasPaused = state.isPaused;

      if (wasPaused) {
        if (_pauseStartTime != null) {
          _totalPausedDuration += DateTime.now().difference(_pauseStartTime!);
          _pauseStartTime = null;
        }
        _elapsedTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => add(const UpdateElapsedTime()),
        );
      } else {
        _pauseStartTime = DateTime.now();
        _elapsedTimer?.cancel();
      }

      emit(state.copyWith(isPaused: !state.isPaused));
    } catch (e) {
      logs.severe('$PauseActivity: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  Future<void> _onCeaseActivity(
    CeaseActivity event,
    Emitter<MapState> emit,
  ) async {
    // Back-to-back Stop taps would hit a null state.activity on the second
    // pass. Treat a second cease as a no-op instead of logging a spurious
    // severe from the null-check crash.
    final activity = state.activity;
    if (activity == null) return;
    try {
      await _ceaseActivityUsecase(activity.id);
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _activityStartTime = null;
      _pauseStartTime = null;
      _totalPausedDuration = Duration.zero;

      emit(
        state.copyWith(
          activity: null,
          elapsedTime: Duration.zero,
          isPaused: false,
        ),
      );
    } catch (e) {
      logs.severe('$CeaseActivity: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  void _onClearError(ClearError event, Emitter<MapState> emit) {
    emit(state.copyWith(error: null));
  }

  void _onUpdateElapsedTime(UpdateElapsedTime event, Emitter<MapState> emit) {
    try {
      if (_activityStartTime == null) return;

      final elapsed =
          DateTime.now().difference(_activityStartTime!) - _totalPausedDuration;
      emit(state.copyWith(elapsedTime: elapsed));
    } catch (e) {
      logs.severe('$UpdateElapsedTime: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  Future<void> _onTracesSearchRequested(
    FetchTraces event,
    Emitter<MapState> emit,
  ) async {
    try {
      final center = event.center;
      final double lat = center.latitude;
      final double lon = center.longitude;
      final double halfBox = kSearchHalfSideDegrees;
      final double left = lon - halfBox;
      final double right = lon + halfBox;
      final double bottom = lat - halfBox;
      final double top = lat + halfBox;

      emit(
        state.copyWith(
          searchCenter: PositionEntity(
            latitude: lat,
            longitude: lon,
            elevation: 0,
          ),
          loadingStatus: LoadingStatus.loadingTraces,
        ),
      );
      final traces = await _getPublicGpsTracesUseCase(
        left,
        bottom,
        right,
        top,
        0,
      );
      emit(state.copyWith(traces: traces));
    } catch (e) {
      logs.severe('$FetchTraces: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    } finally {
      emit(state.copyWith(loadingStatus: null));
    }
  }

  void _onToggleFollowUser(ToggleFollowUser event, Emitter<MapState> emit) {
    emit(state.copyWith(isFollowingUser: !state.isFollowingUser));
  }

  void _onStopFollowingUser(StopFollowingUser event, Emitter<MapState> emit) {
    emit(state.copyWith(isFollowingUser: false));
  }
}
