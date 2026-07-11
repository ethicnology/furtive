import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/activity_entity.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/core/entities/trace_entity.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

part 'map_state.mapper.dart';

@MappableClass()
class MapState with MapStateMappable {
  final Style? style;
  final PositionEntity? userLocation;
  final PositionEntity? searchCenter;
  final AppError? error;
  final List<TraceEntity> traces;
  final LoadingStatus? loadingStatus;
  final ActivityEntity? activity;
  final Duration elapsedTime;
  final bool isPaused;
  final bool isFollowingUser;

  /// Set when a recording was running but the position stream went silent
  /// while the app was backgrounded/locked for longer than the stale
  /// threshold — i.e. the OS suspended or killed the foreground service and
  /// GPS fixes (and therefore the trace) were lost for this long. The UI shows
  /// a one-off banner so the user knows a segment is missing and can consider
  /// the battery-optimisation exemption. Null when tracking is healthy.
  final Duration? trackingGap;

  const MapState({
    this.style,
    this.userLocation,
    this.searchCenter,
    this.error,
    this.traces = const [],
    this.loadingStatus,
    this.activity,
    this.elapsedTime = Duration.zero,
    this.isPaused = false,
    this.isFollowingUser = false,
    this.trackingGap,
  });
}
