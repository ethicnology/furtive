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
import 'package:furtive/core/usecases/activity_notification_use_case.dart';
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
  final _activityNotificationUseCase = ActivityNotificationUseCase();

  late StreamSubscription<PositionEntity> _positionStream;
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

    add(const InitMap());
  }

  void _onUpdateUserLocation(UpdateUserLocation event, Emitter<MapState> emit) {
    try {
      if (state.activity != null) add(ScoreActivity(position: event.position));
      emit(state.copyWith(userLocation: event.position));
    } catch (e) {
      logs.severe('$UpdateUserLocation: $e');
      emit(state.copyWith(errorMessage: AppError(e.toString())));
    }
  }

  @override
  Future<void> close() async {
    await _positionStream.cancel();
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    return super.close();
  }

  Future<void> _onInitMap(InitMap event, Emitter<MapState> emit) async {
    try {
      emit(state.copyWith(loadingStatus: LoadingStatus.localizing));

      final userPositionStream = await _startTrackPositionUsecase();
      _positionStream = userPositionStream
          .handleError((error) => logs.severe('error: $error'))
          .listen((position) => add(UpdateUserLocation(position: position)));

      final userPosition = await _getUserLocationUseCase();
      emit(state.copyWith(userLocation: userPosition));

      emit(state.copyWith(loadingStatus: LoadingStatus.loadingMap));
      final style = await _getMapConfigUseCase();
      emit(state.copyWith(style: style));
    } catch (e) {
      logs.severe('$InitMap: $e');
      emit(state.copyWith(errorMessage: AppError(e.toString())));
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

      emit(state.copyWith(activity: activity));
    } catch (e) {
      logs.severe('$StartActivity: $e');
      emit(state.copyWith(errorMessage: AppError(e.toString())));
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
      final newPoints = [...state.activity!.points, newPoint];
      final updatedActivity = activity.copyWith(points: newPoints);

      emit(state.copyWith(activity: updatedActivity));
    } catch (e) {
      logs.severe('$ScoreActivity: $e');
      emit(
        state.copyWith(
          errorMessage: AppError('$_onScoreActivity: ${e.toString()}'),
        ),
      );
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
      emit(state.copyWith(errorMessage: AppError(e.toString())));
    }
  }

  void _onCeaseActivity(CeaseActivity event, Emitter<MapState> emit) {
    try {
      _ceaseActivityUsecase(state.activity!.id);
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _activityStartTime = null;
      _pauseStartTime = null;
      _totalPausedDuration = Duration.zero;

      _activityNotificationUseCase.cancelActivityNotification();

      emit(
        state.copyWith(
          activity: null,
          elapsedTime: Duration.zero,
          isPaused: false,
        ),
      );
    } catch (e) {
      logs.severe('$CeaseActivity: $e');
      emit(state.copyWith(errorMessage: AppError(e.toString())));
    }
  }

  void _onClearError(ClearError event, Emitter<MapState> emit) {
    emit(state.copyWith(errorMessage: null));
  }

  void _onUpdateElapsedTime(UpdateElapsedTime event, Emitter<MapState> emit) {
    try {
      if (_activityStartTime != null) {
        final elapsed =
            DateTime.now().difference(_activityStartTime!) -
            _totalPausedDuration;
        emit(state.copyWith(elapsedTime: elapsed));

        _activityNotificationUseCase.showActivityNotification(
          activity: state.activity!,
          elapsed: elapsed,
          isPaused: state.isPaused,
        );
      }
    } catch (e) {
      logs.severe('$UpdateElapsedTime: $e');
      emit(state.copyWith(errorMessage: AppError(e.toString())));
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
      emit(state.copyWith(errorMessage: AppError(e.toString())));
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
