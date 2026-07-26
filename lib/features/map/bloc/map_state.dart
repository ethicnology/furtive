import 'package:dart_mappable/dart_mappable.dart';
import 'package:furtive/core/errors.dart';
import 'package:furtive/core/entities/position_entity.dart';
import 'package:furtive/features/map/bloc/map_bloc.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

part 'map_state.mapper.dart';

/// Map presentation state only. Everything about the in-progress recording
/// (activity, elapsed time, pause, tracking gap) lives in RecordingState.
@MappableClass()
class MapState with MapStateMappable {
  const MapState({
    this.style,
    this.userLocation,
    this.error,
    this.loadingStatus,
    this.isFollowingUser = false,
  });

  /// Resolved vector tile style, or null for a tileless map (no
  /// PROTOMAPS_KEY compiled in, or the user opted out of tile fetches).
  final Style? style;
  final PositionEntity? userLocation;
  final AppError? error;
  final LoadingStatus? loadingStatus;

  /// Whether the camera follows the user's position.
  final bool isFollowingUser;
}
