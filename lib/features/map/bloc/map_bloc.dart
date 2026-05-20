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
import 'package:furtive/features/map/bloc/map_event.dart';
import 'package:furtive/features/map/bloc/map_state.dart';
import 'package:furtive/core/usecases/get_map_tile_url_use_case.dart';
import 'package:furtive/core/usecases/get_traces_use_case.dart';
import 'package:furtive/features/map/error.dart';

const double kSearchHalfSideDegrees = 0.01425;

enum LoadingStatus {
  localizing,
  loadingMap,
  loadingTraces,
  startingActivity;

  String get message => switch (this) {
    LoadingStatus.localizing => 'Initializing GPS…',
    LoadingStatus.loadingMap => 'Loading map…',
    LoadingStatus.loadingTraces => 'Loading traces…',
    LoadingStatus.startingActivity => 'Starting activity…',
  };
}

class MapBloc extends Bloc<MapEvent, MapState> {
  final _getMapConfigUseCase = GetMapConfigUseCase();
  final _getPublicGpsTracesUseCase = GetTracesUseCase();
  final _beginActivityUseCase = StartActivityUseCase();
  final _scoreActivityUseCase = ScoreActivityUseCase();
  final _ceaseActivityUsecase = CeaseActivityUseCase();
  final _startTrackPositionUsecase = StartTrackPositionUseCase();
  final _getUserLocationUseCase = GetUserLocationUseCase();

  StreamSubscription<PositionEntity>? _positionStream;
  Timer? _elapsedTimer;
  Timer? _positionWatchdog;
  DateTime? _activityStartTime;
  DateTime? _pauseStartTime;
  Duration _totalPausedDuration = Duration.zero;

  // If the geolocator position stream stays silent for this long while an
  // activity is running and not paused, assume the foreground service was
  // killed (e.g. user swiped the notification away on Android) and cease
  // the activity. Stream.onDone is not reliable for this case — verified
  // against Baseflow/flutter-geolocator issues #1023, #1395.
  static const _positionWatchdogDuration = Duration(seconds: 90);

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
        if (!state.isPaused) _armPositionWatchdog();
      }
      emit(state.copyWith(userLocation: event.position));
    } catch (e) {
      logs.severe('$UpdateUserLocation: $e');
      emit(state.copyWith(error: AppError(e.toString())));
    }
  }

  void _armPositionWatchdog() {
    _positionWatchdog?.cancel();
    _positionWatchdog = Timer(_positionWatchdogDuration, () {
      if (state.activity != null && !state.isPaused) {
        logs.severe(
          'Position stream silent for $_positionWatchdogDuration; '
          'ceasing activity (foreground service likely killed).',
        );
        add(const CeaseActivity());
      }
    });
  }

  @override
  Future<void> close() async {
    await _positionStream?.cancel();
    _elapsedTimer?.cancel();
    _positionWatchdog?.cancel();
    return super.close();
  }

  Future<void> _onInitMap(InitMap event, Emitter<MapState> emit) async {
    try {
      emit(state.copyWith(loadingStatus: LoadingStatus.localizing));

      // B38: InitMap can fire more than once (from the onboarding finish and
      // from PreferencesBloc.UpdatePreferences). Cancel the previous
      // subscription before opening a new one so we don't leak listeners
      // that keep dispatching UpdateUserLocation events.
      await _positionStream?.cancel();
      final userPositionStream = await _startTrackPositionUsecase();
      _positionStream = userPositionStream
          .handleError((error) => logs.severe('error: $error'))
          .listen(
            (position) => add(UpdateUserLocation(position: position)),
            // When the user swipes the geolocator foreground-service
            // notification away, the position stream closes. Treat that as
            // an explicit "stop tracking" gesture and end any active activity.
            onDone: () {
              if (state.activity != null) add(const CeaseActivity());
            },
          );

      final userPosition = await _getUserLocationUseCase();
      emit(state.copyWith(userLocation: userPosition));

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
      _armPositionWatchdog();

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
    if (state.activity == null) throw ActivityNotStartedError();

    final activity = state.activity!;
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
      // Use the locally-captured `activity` (line above the await), not
      // state.activity — a concurrent CeaseActivity between the await and
      // here would null state.activity and crash the null-bang.
      final newPoints = [...activity.points, newPoint];
      final updatedActivity = activity.copyWith(points: newPoints);

      emit(state.copyWith(activity: updatedActivity));
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
        _armPositionWatchdog();
      } else {
        _pauseStartTime = DateTime.now();
        _elapsedTimer?.cancel();
        _positionWatchdog?.cancel();
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
    try {
      await _ceaseActivityUsecase(state.activity!.id);
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _positionWatchdog?.cancel();
      _positionWatchdog = null;
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
